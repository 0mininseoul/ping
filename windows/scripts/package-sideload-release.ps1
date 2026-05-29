[CmdletBinding()]
param(
    [string]$Version,
    [ValidateSet("x64", "ARM64")]
    [string[]]$Platform = @("x64", "ARM64"),
    [string]$DistRoot = (Join-Path $PSScriptRoot "..\dist"),
    [string]$CertificatePath = (Join-Path $PSScriptRoot "..\certs\Ping-Windows-Sideload.cer"),
    [string]$InstallerScriptPath = (Join-Path $PSScriptRoot "install-ping-windows.ps1"),
    [switch]$AllowUnsigned
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

function Get-PackageArchitectureLabel([string]$TargetPlatform) {
    if ($TargetPlatform -eq "ARM64") {
        return "arm64"
    }

    return "x64"
}

function Test-SignatureMatchesTrustedCertificate($Signature, [string]$ExpectedCertificatePath) {
    if (-not $Signature.SignerCertificate) {
        return $false
    }

    $expectedCertificate = [Security.Cryptography.X509Certificates.X509Certificate2]::new($ExpectedCertificatePath)
    return $Signature.SignerCertificate.Thumbprint -eq $expectedCertificate.Thumbprint
}

function Assert-SignedPackage([string]$PackagePath, [string]$ExpectedCertificatePath) {
    $signature = Get-AuthenticodeSignature -LiteralPath $PackagePath
    Write-Host "$(Split-Path -Leaf $PackagePath): signature $($signature.Status)"

    if (Test-SignatureMatchesTrustedCertificate $signature $ExpectedCertificatePath) {
        if ($signature.Status -ne "Valid") {
            Write-Warning "Package signature status is $($signature.Status), but the signer matches the committed Ping sideload certificate: $PackagePath"
        }

        return
    }

    if ($AllowUnsigned) {
        Write-Warning "Keeping unsigned package because -AllowUnsigned was provided: $PackagePath"
        return
    }

    if ($signature.Status -eq "Valid") {
        throw "Package is signed, but the signer does not match the committed Ping sideload certificate: $PackagePath"
    }

    throw "Package is not signed with the committed Ping sideload certificate: $PackagePath"
}

if ([string]::IsNullOrWhiteSpace($Version)) {
    $Version = Get-PingWindowsPackageVersion
}

if (-not (Test-Path -LiteralPath $DistRoot)) {
    throw "Release dist directory does not exist: $DistRoot"
}

if (-not (Test-Path -LiteralPath $CertificatePath)) {
    throw "Missing public sideload certificate: $CertificatePath"
}

if (-not (Test-Path -LiteralPath $InstallerScriptPath)) {
    throw "Missing installer script: $InstallerScriptPath"
}

$releaseRoot = Join-Path $DistRoot "Ping-Windows-v$Version-sideload"
$releaseZip = Join-Path $DistRoot "Ping-Windows-v$Version-sideload.zip"
Remove-Item -Recurse -Force -LiteralPath $releaseRoot -ErrorAction SilentlyContinue
Remove-Item -Force -LiteralPath $releaseZip -ErrorAction SilentlyContinue
New-Item -ItemType Directory -Force -Path $releaseRoot | Out-Null

foreach ($targetPlatform in $Platform) {
    $architectureLabel = Get-PackageArchitectureLabel $targetPlatform
    $source = Join-Path $DistRoot "Ping-Windows-v$Version-$architectureLabel.msix"
    if (-not (Test-Path -LiteralPath $source)) {
        throw "Missing release package: $source"
    }

    Assert-SignedPackage $source $CertificatePath
    Copy-Item -LiteralPath $source -Destination (Join-Path $releaseRoot (Split-Path -Leaf $source)) -Force
}

Copy-Item -LiteralPath $CertificatePath -Destination (Join-Path $releaseRoot "Ping-Windows-Sideload.cer") -Force
Copy-Item -LiteralPath $InstallerScriptPath -Destination (Join-Path $releaseRoot "install-ping-windows.ps1") -Force
$icoSource = Join-Path $windowsRoot "installer\app.ico"
if (Test-Path -LiteralPath $icoSource) {
    Copy-Item -LiteralPath $icoSource -Destination (Join-Path $releaseRoot "app.ico") -Force
}

$distributionNotice = if ($AllowUnsigned) {
    "This bundle was created with -AllowUnsigned for CI/build validation. Do not distribute it to users."
} else {
    "This is the zero-cost sideload distribution package. It uses a self-signed MSIX certificate, so Windows must trust Ping-Windows-Sideload.cer before installing."
}

$readme = @"
Ping for Windows v$Version

$distributionNotice

Install:
1. Right-click PowerShell and choose Run as administrator.
2. cd to this folder.
3. Run:
   powershell -ExecutionPolicy Bypass -File .\install-ping-windows.ps1

The script imports Ping-Windows-Sideload.cer into LocalMachine\TrustedPeople,
chooses x64 or arm64 for this PC, installs the MSIX, and launches Ping.

For a publicly trusted one-click install, Ping needs Microsoft Store submission
or a paid public code-signing route. This folder is the free sideload route.
"@
Set-Content -LiteralPath (Join-Path $releaseRoot "README.txt") -Value $readme -Encoding utf8

$checksums = Get-ChildItem -LiteralPath $releaseRoot -File |
    Sort-Object Name |
    ForEach-Object {
        $hash = Get-FileHash -LiteralPath $_.FullName -Algorithm SHA256
        "$($hash.Hash.ToLowerInvariant())  $($_.Name)"
    }
Set-Content -LiteralPath (Join-Path $releaseRoot "SHA256SUMS.txt") -Value $checksums -Encoding ascii

Compress-Archive -Path (Join-Path $releaseRoot "*") -DestinationPath $releaseZip -Force
Write-Host "Wrote $releaseRoot"
Write-Host "Wrote $releaseZip"
