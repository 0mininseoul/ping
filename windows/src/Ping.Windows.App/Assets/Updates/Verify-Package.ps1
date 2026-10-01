param([Parameter(Mandatory=$true)][string]$PackagePath)
$ErrorActionPreference = 'Stop'
[Console]::OutputEncoding = [Text.UTF8Encoding]::new($false)
$signature = Get-AuthenticodeSignature -LiteralPath $PackagePath
@{
    IsTrusted = ($signature.Status -eq 'Valid')
    Thumbprint = [string]$signature.SignerCertificate.Thumbprint
    Subject = [string]$signature.SignerCertificate.Subject
} | ConvertTo-Json -Compress
