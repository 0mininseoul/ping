[CmdletBinding()]
param(
    [string]$NativeDllPath,
    [string]$OutputPath,
    [int]$DurationMs = 3000,
    [int]$MonitorIndex = -1,
    [double]$FaceDiameterRatio = 0.32,
    [switch]$AllowSmallMonitor
)

$ErrorActionPreference = "Stop"

$repoRoot = Resolve-Path (Join-Path $PSScriptRoot "..\..")

if ([string]::IsNullOrWhiteSpace($NativeDllPath)) {
    $candidates = Get-ChildItem -Path $repoRoot -Recurse -Filter "Ping.Windows.NativeCapture.dll" -ErrorAction SilentlyContinue |
        Sort-Object LastWriteTime -Descending

    if ($candidates.Count -eq 0) {
        throw "Ping.Windows.NativeCapture.dll was not found. Build the Windows solution first, or pass -NativeDllPath."
    }

    $NativeDllPath = $candidates[0].FullName
}

if ([string]::IsNullOrWhiteSpace($OutputPath)) {
    $tempDir = Join-Path ([System.IO.Path]::GetTempPath()) "Ping"
    New-Item -ItemType Directory -Force -Path $tempDir | Out-Null
    $OutputPath = Join-Path $tempDir ("screen-face-smoke-{0:yyyyMMdd-HHmmss-fff}.mp4" -f [DateTimeOffset]::UtcNow)
}

$NativeDllPath = (Resolve-Path $NativeDllPath).Path

$source = @"
using System;
using System.Runtime.InteropServices;

public static class PingCaptureSmokeNative
{
    [UnmanagedFunctionPointer(CallingConvention.Winapi)]
    private delegate int SelfTestDelegate();

    [UnmanagedFunctionPointer(CallingConvention.Winapi, CharSet = CharSet.Unicode)]
    private delegate int RecordDelegate(
        string outputPath,
        int durationMs,
        int targetMonitorIndex,
        double faceDiameterRatio,
        out double aspectRatio);

    public static int SelfTest(IntPtr library)
    {
        IntPtr export = NativeLibrary.GetExport(library, "PingCapture_SelfTestScreenCapture");
        var callback = Marshal.GetDelegateForFunctionPointer<SelfTestDelegate>(export);
        return callback();
    }

    public static int Record(IntPtr library, string outputPath, int durationMs, int monitorIndex, double faceDiameterRatio, out double aspectRatio)
    {
        IntPtr export = NativeLibrary.GetExport(library, "PingCapture_RecordScreenFaceMp4");
        var callback = Marshal.GetDelegateForFunctionPointer<RecordDelegate>(export);
        return callback(outputPath, durationMs, monitorIndex, faceDiameterRatio, out aspectRatio);
    }
}
"@

Add-Type -TypeDefinition $source

$library = [System.Runtime.InteropServices.NativeLibrary]::Load($NativeDllPath)
try {
    Write-Host "Native DLL: $NativeDllPath"

    $selfTestCode = [PingCaptureSmokeNative]::SelfTest($library)
    Write-Host "Self-test code: $selfTestCode"
    if ($selfTestCode -ne 0) {
        throw "Screen capture self-test failed with native code $selfTestCode."
    }

    $aspectRatio = 0.0
    $recordCode = [PingCaptureSmokeNative]::Record(
        $library,
        $OutputPath,
        $DurationMs,
        $MonitorIndex,
        $FaceDiameterRatio,
        [ref]$aspectRatio)

    Write-Host "Record code: $recordCode"
    Write-Host "Aspect ratio: $aspectRatio"
    Write-Host "Output path: $OutputPath"

    if ($recordCode -ne 0) {
        throw "Screen-face recording failed with native code $recordCode."
    }

    $file = Get-Item -LiteralPath $OutputPath -ErrorAction Stop
    if ($file.Length -le 0) {
        throw "MP4 file exists but is empty: $OutputPath"
    }

    Write-Host "MP4 bytes: $($file.Length)"

    $ffprobe = Get-Command ffprobe -ErrorAction Stop
    $probeJson = & $ffprobe.Source -v error -show_entries format=duration -show_entries stream=codec_type,width,height -of json "$OutputPath"
    $probe = $probeJson | ConvertFrom-Json
    $duration = [double]$probe.format.duration
    if ($duration -lt 2.9 -or $duration -gt 3.2) {
        throw "Expected 2.9-3.2s duration, got $duration seconds."
    }

    $videoStream = @($probe.streams | Where-Object { $_.codec_type -eq "video" } | Select-Object -First 1)[0]
    if (-not $videoStream) {
        throw "ffprobe did not find a video stream."
    }

    $width = [int]$videoStream.width
    $height = [int]$videoStream.height
    if ($width -lt 1280 -and -not $AllowSmallMonitor) {
        throw "Expected video width >= 1280px unless using -AllowSmallMonitor, got ${width}x${height}."
    }

    Write-Host "Verified duration: $duration"
    Write-Host "Verified resolution: ${width}x${height}"
    Write-Warning "Manual check still required: bottom-right face PIP visibility, Windows Media Player playback, and macOS QuickTime playback."
}
finally {
    [System.Runtime.InteropServices.NativeLibrary]::Free($library)
}
