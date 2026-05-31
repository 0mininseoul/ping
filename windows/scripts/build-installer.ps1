[CmdletBinding()]
param(
    [string]$Version,
    [string]$DistRoot = (Join-Path $PSScriptRoot "..\dist"),
    [string]$PayloadRoot,
    [string]$PackageBaseUrl = "https://0minping.vercel.app/downloads/windows",
    [string]$InnoSetupCompilerPath,
    [string]$InnoScriptPath = (Join-Path $PSScriptRoot "..\installer\PingSetup.iss")
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$windowsRoot = Resolve-Path (Join-Path $PSScriptRoot "..")
$appProjectRoot = Join-Path $windowsRoot "src\Ping.Windows.App"

function Get-PingWindowsPackageVersion {
    $manifestPath = Join-Path $appProjectRoot "Package.appxmanifest"
    [xml]$manifest = Get-Content -Raw -LiteralPath $manifestPath
    $identityVersion = [string]$manifest.Package.Identity.Version
    $match = [regex]::Match($identityVersion, '^(?<version>\d+\.\d+\.\d+)\.0$')
    if (-not $match.Success) {
        throw "Package.appxmanifest Identity.Version must use major.minor.patch.0 format. Found $identityVersion."
    }

    return $match.Groups["version"].Value
}

function Resolve-InnoSetupCompiler {
    if (-not [string]::IsNullOrWhiteSpace($InnoSetupCompilerPath)) {
        if (-not (Test-Path -LiteralPath $InnoSetupCompilerPath)) {
            throw "Inno Setup compiler was not found: $InnoSetupCompilerPath"
        }

        return $InnoSetupCompilerPath
    }

    $command = Get-Command ISCC.exe -ErrorAction SilentlyContinue
    if ($command) {
        return $command.Source
    }

    $candidates = @(
        (Join-Path ${env:ProgramFiles(x86)} "Inno Setup 6\ISCC.exe"),
        (Join-Path $env:ProgramFiles "Inno Setup 6\ISCC.exe")
    )
    foreach ($candidate in $candidates) {
        if (Test-Path -LiteralPath $candidate) {
            return $candidate
        }
    }

    throw "ISCC.exe was not found. Install Inno Setup 6 before building the Windows setup EXE."
}

function Assert-InstallerPayload([string]$Root, [string]$TargetVersion) {
    $requiredFiles = @(
        "Ping-Windows-Sideload.cer",
        "install-ping-windows.ps1",
        "uninstall-ping-windows.ps1",
        "dependencies-x64.txt",
        "dependencies-arm64.txt"
    )

    foreach ($file in $requiredFiles) {
        $path = Join-Path $Root $file
        if (-not (Test-Path -LiteralPath $path)) {
            throw "Missing installer payload file: $path"
        }
    }

    foreach ($architectureLabel in @("x64", "arm64")) {
        $msixPath = Join-Path $Root "Ping-Windows-v$TargetVersion-$architectureLabel.msix"
        if (-not (Test-Path -LiteralPath $msixPath)) {
            throw "Missing installer MSIX payload: $msixPath"
        }

        $dependencyRoot = Join-Path $Root "Dependencies\$architectureLabel"
        if (-not (Test-Path -LiteralPath $dependencyRoot)) {
            throw "Missing installer dependency directory: $dependencyRoot"
        }

        $dependencyPackages = Get-ChildItem -LiteralPath $dependencyRoot -File |
            Where-Object { $_.Extension -in @(".msix", ".appx") }
        if (-not $dependencyPackages) {
            throw "Installer dependency directory has no MSIX/AppX packages: $dependencyRoot"
        }
    }
}

if ([string]::IsNullOrWhiteSpace($Version)) {
    $Version = Get-PingWindowsPackageVersion
}

if ([string]::IsNullOrWhiteSpace($PayloadRoot)) {
    $PayloadRoot = Join-Path $DistRoot "Ping-Windows-v$Version-sideload"
}

if (-not (Test-Path -LiteralPath $DistRoot)) {
    throw "Release dist directory does not exist: $DistRoot"
}

if (-not (Test-Path -LiteralPath $PayloadRoot)) {
    throw "Installer payload directory does not exist: $PayloadRoot"
}

if (-not (Test-Path -LiteralPath $InnoScriptPath)) {
    throw "Inno Setup script does not exist: $InnoScriptPath"
}

Assert-InstallerPayload $PayloadRoot $Version
$compiler = Resolve-InnoSetupCompiler
$resolvedPayloadRoot = (Resolve-Path -LiteralPath $PayloadRoot).Path
$resolvedDistRoot = (Resolve-Path -LiteralPath $DistRoot).Path
$setupPath = Join-Path $resolvedDistRoot "PingSetup-v$Version.exe"
Remove-Item -Force -LiteralPath $setupPath -ErrorAction SilentlyContinue

$previousVersion = $env:PING_VERSION
$previousPayload = $env:PING_INSTALLER_PAYLOAD_ROOT
$previousOutput = $env:PING_INSTALLER_OUTPUT_DIR
$previousPackageBaseUrl = $env:PING_INSTALLER_PACKAGE_BASE_URL
try {
    $env:PING_VERSION = $Version
    $env:PING_INSTALLER_PAYLOAD_ROOT = $resolvedPayloadRoot
    $env:PING_INSTALLER_OUTPUT_DIR = $resolvedDistRoot
    $env:PING_INSTALLER_PACKAGE_BASE_URL = $PackageBaseUrl

    & $compiler $InnoScriptPath
    if ($LASTEXITCODE -ne 0) {
        throw "Inno Setup compiler failed with exit code $LASTEXITCODE."
    }
}
finally {
    $env:PING_VERSION = $previousVersion
    $env:PING_INSTALLER_PAYLOAD_ROOT = $previousPayload
    $env:PING_INSTALLER_OUTPUT_DIR = $previousOutput
    $env:PING_INSTALLER_PACKAGE_BASE_URL = $previousPackageBaseUrl
}

if (-not (Test-Path -LiteralPath $setupPath)) {
    throw "Inno Setup completed but did not create $setupPath."
}

Write-Host "Wrote $setupPath"
