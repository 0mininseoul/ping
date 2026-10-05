[CmdletBinding()]
param(
    [ValidateSet('x64', 'ARM64')][string]$Platform = 'x64',
    [ValidateSet('Debug', 'Release')][string]$Configuration = 'Debug',
    [switch]$SkipBuild,
    [switch]$ConversationOnly,
    [ValidatePattern('^\\\\\.\\DISPLAY[1-9][0-9]*$')][string]$MonitorDeviceName
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$windowsRoot = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
if (-not $SkipBuild) { & (Join-Path $PSScriptRoot 'build-local.ps1') -Platform $Platform -Configuration $Configuration -UiSmoke }
$rid = if ($Platform -eq 'ARM64') { 'win-arm64' } else { 'win-x64' }
$executable = Join-Path $windowsRoot "artifacts\ui-smoke\bin\$Platform\$Configuration\net10.0-windows10.0.26100.0\$rid\Ping.Windows.App.exe"
if (-not (Test-Path -LiteralPath $executable)) { throw 'Build the isolated UI fixture first.' }
$outputDirectory = Join-Path $windowsRoot ('artifacts\ui-shell-' + [Guid]::NewGuid().ToString('N'))
$previousDisplay = $env:PING_UI_SMOKE_DISPLAY
try {
    $env:PING_UI_SMOKE_DISPLAY = $MonitorDeviceName
    $route = if ($ConversationOnly) { '--ui-conversation-output' } else { '--ui-smoke-output' }
    $process = Start-Process -FilePath $executable -ArgumentList "$route `"$outputDirectory`"" -PassThru -WindowStyle Hidden
} finally { $env:PING_UI_SMOKE_DISPLAY = $previousDisplay }
if (-not $process.WaitForExit(60000)) {
    Stop-Process -Id $process.Id -ErrorAction SilentlyContinue
    throw "Isolated UI fixture timed out. Diagnostics: $outputDirectory"
}
$resultPath = Join-Path $outputDirectory 'result.json'
if (-not (Test-Path -LiteralPath $resultPath)) { throw "UI fixture exited without a result (exit $($process.ExitCode)). Diagnostics: $outputDirectory" }
$result = Get-Content -LiteralPath $resultPath -Raw | ConvertFrom-Json
if (-not $result.Success) { throw "UI fixture failed: $($result.Error). Diagnostics: $outputDirectory" }
Write-Host "PASS: $($result.Checks.Count) actual WinUI checks. Rendered artifacts: $outputDirectory"
