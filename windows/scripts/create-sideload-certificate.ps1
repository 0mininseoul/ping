[CmdletBinding()]
param(
    [string]$Subject = "CN=Youngmin Park",
    [string]$FriendlyName = "Ping Windows Sideload",
    [int]$YearsValid = 10,
    [string]$OutputDirectory = (Join-Path $PSScriptRoot "..\certs\private"),
    [string]$PublicCertificatePath = (Join-Path $PSScriptRoot "..\certs\Ping-Windows-Sideload.cer"),
    [securestring]$Password
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

if (-not $IsWindows) {
    throw "Self-signed package certificates must be created on Windows with New-SelfSignedCertificate."
}

if ($YearsValid -lt 1) {
    throw "YearsValid must be at least 1."
}

if (-not $Password) {
    $Password = Read-Host "PFX password for GitHub secret PING_WINDOWS_CERT_PASSWORD" -AsSecureString
}

New-Item -ItemType Directory -Force -Path $OutputDirectory | Out-Null
New-Item -ItemType Directory -Force -Path (Split-Path -Parent $PublicCertificatePath) | Out-Null

$certificate = New-SelfSignedCertificate `
    -Type Custom `
    -Subject $Subject `
    -FriendlyName $FriendlyName `
    -KeyAlgorithm RSA `
    -KeyLength 2048 `
    -KeyUsage DigitalSignature `
    -CertStoreLocation "Cert:\CurrentUser\My" `
    -NotAfter (Get-Date).AddYears($YearsValid) `
    -TextExtension @(
        "2.5.29.37={text}1.3.6.1.5.5.7.3.3",
        "2.5.29.19={text}"
    )

$safeName = ($FriendlyName -replace '[^A-Za-z0-9._-]', '-').Trim('-')
$pfxPath = Join-Path $OutputDirectory "$safeName.pfx"
$base64Path = Join-Path $OutputDirectory "$safeName.pfx.base64.txt"

Export-PfxCertificate -Cert $certificate -FilePath $pfxPath -Password $Password | Out-Null
Export-Certificate -Cert $certificate -FilePath $PublicCertificatePath -Type CERT | Out-Null

$pfxBase64 = [Convert]::ToBase64String([IO.File]::ReadAllBytes($pfxPath))
Set-Content -LiteralPath $base64Path -Value $pfxBase64 -Encoding ascii -NoNewline

Write-Host "Created public certificate: $PublicCertificatePath"
Write-Host "Created private PFX: $pfxPath"
Write-Host "Created base64 secret payload: $base64Path"
Write-Host ""
Write-Host "Set GitHub secrets with:"
Write-Host "  Get-Content -Raw `"$base64Path`" | gh secret set PING_WINDOWS_CERT_BASE64"
Write-Host "  gh secret set PING_WINDOWS_CERT_PASSWORD"
Write-Host ""
Write-Warning "Commit only the .cer file. Do not commit the .pfx file, base64 payload, or password."
