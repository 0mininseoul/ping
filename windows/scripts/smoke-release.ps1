[CmdletBinding()]
param(
    [string]$Version,
    [ValidateSet("x64", "ARM64")]
    [string[]]$Platform = @("x64", "ARM64"),
    [switch]$Install,
    [switch]$AllowUnsigned
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$windowsRoot = Resolve-Path (Join-Path $PSScriptRoot "..")
$repoRoot = Resolve-Path (Join-Path $windowsRoot "..")
$distRoot = Join-Path $windowsRoot "dist"
$expectedIdentityName = "YoungminPark.PingWindows"

function Get-PingMarketingVersion {
    $projectYml = Join-Path $repoRoot "project.yml"
    $contents = Get-Content -Raw -LiteralPath $projectYml
    $match = [regex]::Match($contents, 'MARKETING_VERSION:\s*"([^"]+)"')
    if (-not $match.Success) {
        throw "Could not read MARKETING_VERSION from project.yml."
    }

    return $match.Groups[1].Value
}

function Get-PackageArchitectureLabel([string]$TargetPlatform) {
    if ($TargetPlatform -eq "ARM64") {
        return "arm64"
    }

    return "x64"
}

function Get-PackageArchitectureManifestValue([string]$TargetPlatform) {
    if ($TargetPlatform -eq "ARM64") {
        return "arm64"
    }

    return "x64"
}

function Assert-PackageContainsNativeCaptureDll($Archive, [string]$PackagePath) {
    $nativeDllEntry = $Archive.Entries |
        Where-Object { $_.Name -eq "Ping.Windows.NativeCapture.dll" } |
        Select-Object -First 1

    if (-not $nativeDllEntry) {
        throw "Package $PackagePath does not contain Ping.Windows.NativeCapture.dll."
    }

    if ($nativeDllEntry.Length -le 0) {
        throw "Package $PackagePath contains an empty Ping.Windows.NativeCapture.dll."
    }
}

function Assert-PingPackageIdentity([string]$PackagePath, [string]$ExpectedVersion, [string]$ExpectedArchitecture) {
    Add-Type -AssemblyName System.IO.Compression.FileSystem
    $archive = [System.IO.Compression.ZipFile]::OpenRead($PackagePath)
    try {
        $manifestEntry = $archive.Entries | Where-Object { $_.FullName -eq "AppxManifest.xml" } | Select-Object -First 1
        if (-not $manifestEntry) {
            throw "Package $PackagePath does not contain AppxManifest.xml."
        }

        $stream = $manifestEntry.Open()
        try {
            $reader = [System.IO.StreamReader]::new($stream)
            try {
                [xml]$manifest = $reader.ReadToEnd()
            }
            finally {
                $reader.Dispose()
            }
        }
        finally {
            $stream.Dispose()
        }

        $identity = $manifest.Package.Identity
        if ($identity.Name -ne $expectedIdentityName) {
            throw "Package identity $($identity.Name) is not $expectedIdentityName."
        }

        if ($identity.Version -ne "$ExpectedVersion.0") {
            throw "Package version $($identity.Version) does not match $ExpectedVersion.0."
        }

        if ($identity.ProcessorArchitecture -ne $ExpectedArchitecture) {
            throw "Package architecture $($identity.ProcessorArchitecture) does not match $ExpectedArchitecture."
        }

        Assert-PackageContainsNativeCaptureDll $archive $PackagePath
    }
    finally {
        $archive.Dispose()
    }
}

if ([string]::IsNullOrWhiteSpace($Version)) {
    $Version = Get-PingMarketingVersion
}

$configPath = Join-Path $env:LOCALAPPDATA "Ping\Supabase.json"
if (-not (Test-Path -LiteralPath $configPath)) {
    Write-Warning "Supabase config was not found at $configPath. The app can install, but runtime auth/backend smoke tests will fail."
}

foreach ($targetPlatform in $Platform) {
    $architectureLabel = Get-PackageArchitectureLabel $targetPlatform
    $architectureManifestValue = Get-PackageArchitectureManifestValue $targetPlatform
    $packagePath = Join-Path $distRoot "Ping-Windows-v$Version-$architectureLabel.msix"
    if (-not (Test-Path -LiteralPath $packagePath)) {
        throw "Missing release package: $packagePath"
    }

    $package = Get-Item -LiteralPath $packagePath
    if ($package.Length -le 0) {
        throw "Package is empty: $packagePath"
    }

    Assert-PingPackageIdentity $packagePath $Version $architectureManifestValue

    $signature = Get-AuthenticodeSignature -LiteralPath $packagePath
    Write-Host "$($package.Name): $($package.Length) bytes, signature $($signature.Status)"
    if ($signature.Status -ne "Valid" -and -not $AllowUnsigned) {
        throw "Package is not signed with a trusted certificate. Re-run with -AllowUnsigned only for local CI/build validation."
    }
}

if ($Install) {
    $currentArchitecture = if ([System.Runtime.InteropServices.RuntimeInformation]::ProcessArchitecture -eq "Arm64") {
        "ARM64"
    } else {
        "x64"
    }
    $currentArchitectureLabel = Get-PackageArchitectureLabel $currentArchitecture
    $installPackage = Join-Path $distRoot "Ping-Windows-v$Version-$currentArchitectureLabel.msix"
    if (-not (Test-Path -LiteralPath $installPackage)) {
        throw "Could not find package for current architecture: $installPackage"
    }

    Add-AppxPackage -LiteralPath $installPackage -ForceUpdateFromAnyVersion
    $installed = Get-AppxPackage -Name "YoungminPark.PingWindows" |
        Sort-Object InstallDate -Descending |
        Select-Object -First 1
    if (-not $installed) {
        throw "Ping package did not appear in Get-AppxPackage after installation."
    }

    Start-Process "shell:AppsFolder\$($installed.PackageFamilyName)!App"
    Write-Warning "Manual smoke still required: onboarding probes, Alt+P, Alt+L, Alt+Shift+L, notification click playback, and Mac/Windows cross-send."
}
