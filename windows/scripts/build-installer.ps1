[CmdletBinding()]
param(
    [string]$Version,
    [string]$DistRoot = (Join-Path $PSScriptRoot "..\dist"),
    [string]$PayloadRoot,
    [string]$PackageBaseUrl = "https://ping0min.vercel.app/downloads/windows",
    [string]$InnoSetupCompilerPath,
    [string]$InnoScriptPath = (Join-Path $PSScriptRoot "..\installer\PingSetup.iss")
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$windowsRoot = Resolve-Path (Join-Path $PSScriptRoot "..")
$repoRoot = Resolve-Path (Join-Path $windowsRoot "..")

function Get-PingMarketingVersion {
    $projectYml = Join-Path $repoRoot "project.yml"
    $contents = Get-Content -Raw -LiteralPath $projectYml
    $match = [regex]::Match($contents, 'MARKETING_VERSION:\s*"([^"]+)"')
    if (-not $match.Success) {
        throw "Could not read MARKETING_VERSION from project.yml."
    }

    return $match.Groups[1].Value
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
        "install-ping-windows.ps1"
    )

    foreach ($file in $requiredFiles) {
        $path = Join-Path $Root $file
        if (-not (Test-Path -LiteralPath $path)) {
            throw "Missing installer payload file: $path"
        }
    }
}

if ([string]::IsNullOrWhiteSpace($Version)) {
    $Version = Get-PingMarketingVersion
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
