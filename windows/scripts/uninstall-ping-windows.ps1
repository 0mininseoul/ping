[CmdletBinding()]
param(
    [string]$CertificatePath = (Join-Path $PSScriptRoot "Ping-Windows-Sideload.cer")
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$packageName = "YoungminPark.PingWindows"

function Remove-ShortcutIfPresent([string]$Path) {
    if (Test-Path -LiteralPath $Path) {
        Remove-Item -LiteralPath $Path -Force -ErrorAction SilentlyContinue
    }
}

function Remove-PingCertificate([string]$TrustedCertificatePath) {
    if (-not (Test-Path -LiteralPath $TrustedCertificatePath)) {
        return
    }

    $expectedCertificate = [Security.Cryptography.X509Certificates.X509Certificate2]::new($TrustedCertificatePath)
    $thumbprint = $expectedCertificate.Thumbprint
    $stores = @(
        "Cert:\LocalMachine\TrustedPeople\$thumbprint",
        "Cert:\CurrentUser\TrustedPeople\$thumbprint"
    )

    foreach ($storePath in $stores) {
        if (Test-Path -LiteralPath $storePath) {
            Remove-Item -LiteralPath $storePath -Force -ErrorAction SilentlyContinue
        }
    }
}

try {
    $packages = @(Get-AppxPackage -Name $packageName -AllUsers -ErrorAction SilentlyContinue)
    if ($packages.Count -eq 0) {
        $packages = @(Get-AppxPackage -Name $packageName -ErrorAction SilentlyContinue)
    }

    foreach ($package in $packages) {
        try {
            Remove-AppxPackage -Package $package.PackageFullName -AllUsers -ErrorAction Stop
        }
        catch {
            Remove-AppxPackage -Package $package.PackageFullName -ErrorAction SilentlyContinue
        }
    }

    Remove-ShortcutIfPresent ([System.IO.Path]::Combine([System.Environment]::GetFolderPath("Desktop"), "Ping.lnk"))
    Remove-ShortcutIfPresent ([System.IO.Path]::Combine([System.Environment]::GetFolderPath("Startup"), "Ping.lnk"))

    $startMenuFolder = [System.IO.Path]::Combine([System.Environment]::GetFolderPath("Programs"), "Ping")
    Remove-ShortcutIfPresent ([System.IO.Path]::Combine($startMenuFolder, "Ping.lnk"))
    if ((Test-Path -LiteralPath $startMenuFolder) -and -not (Get-ChildItem -LiteralPath $startMenuFolder -Force -ErrorAction SilentlyContinue)) {
        Remove-Item -LiteralPath $startMenuFolder -Force -ErrorAction SilentlyContinue
    }

    Remove-PingCertificate $CertificatePath

    $localIconPath = Join-Path $env:LOCALAPPDATA "Ping\app.ico"
    Remove-ShortcutIfPresent $localIconPath

    Write-Host "Ping for Windows has been uninstalled."
}
catch {
    try {
        Add-Type -AssemblyName PresentationFramework -ErrorAction SilentlyContinue
        [System.Windows.MessageBox]::Show("Ping 제거 중 오류가 발생했습니다:`n`n$($_.Exception.Message)", "Ping 제거 오류", "OK", "Error") | Out-Null
    }
    catch {
        Write-Error "Ping 제거 오류: $($_.Exception.Message)"
    }
    throw $_
}
