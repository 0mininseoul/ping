param(
    [Parameter(Mandatory=$true)][string]$PackagePath,
    [Parameter(Mandatory=$true)][string]$DependencyListPath,
    [Parameter(Mandatory=$true)][string]$ExpectedVersion,
    [string]$ExpectedThumbprint = '12D9D5539B1851EE1A0725CCFCB6A9CCD098DCDC',
    [int]$WaitForPid = 0,
    [switch]$ValidateOnly
)
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$packageName = 'YoungminPark.PingWindows'
$resultPath = Join-Path (Split-Path -Parent $PackagePath) 'update-result.json'
try {
    $signature = Get-AuthenticodeSignature -LiteralPath $PackagePath
    if ($signature.Status -ne 'Valid' -or -not $signature.SignerCertificate -or $signature.SignerCertificate.Thumbprint -ne $ExpectedThumbprint) {
        throw 'The Ping update signature is invalid.'
    }
    Add-Type -AssemblyName System.IO.Compression.FileSystem
    $archive = [IO.Compression.ZipFile]::OpenRead($PackagePath)
    try {
        $entry = $archive.GetEntry('AppxManifest.xml')
        if (-not $entry -or $entry.Length -gt 131072) { throw 'The package manifest is invalid.' }
        $reader = [IO.StreamReader]::new($entry.Open())
        try { [xml]$manifest = $reader.ReadToEnd() } finally { $reader.Dispose() }
        $identity = $manifest.Package.Identity
        if ($identity.Name -ne $packageName -or $identity.Publisher -ne 'CN=Youngmin Park' -or $identity.Version -ne $ExpectedVersion) {
            throw 'The update identity does not match Ping.'
        }
    } finally { $archive.Dispose() }
    $dependencies = @(Get-Content -LiteralPath $DependencyListPath -Raw -Encoding UTF8 | ConvertFrom-Json)
    if ($dependencies.Count -eq 0) { throw 'Update dependencies are missing.' }
    foreach ($dependency in $dependencies) {
        $dependencySignature = Get-AuthenticodeSignature -LiteralPath $dependency
        if ($dependencySignature.Status -ne 'Valid' -or -not $dependencySignature.SignerCertificate -or
            $dependencySignature.SignerCertificate.Subject -notmatch '(^|, )O=Microsoft Corporation(,|$)') {
            throw 'An update dependency signature is invalid.'
        }
    }
    if ($ValidateOnly) { Write-Output 'Verified Ping identity, version and signatures.'; exit 0 }
    $running = if ($WaitForPid -gt 0) { Get-Process -Id $WaitForPid -ErrorAction SilentlyContinue } else { $null }
    if ($running -and -not $running.WaitForExit(120000)) { throw 'Ping did not finish shutting down.' }
    $installed = Get-AppxPackage -Name $packageName
    if (-not $installed) { throw 'Ping is not installed for this Windows user.' }
    if ([version]$installed.Version -ge [version]$ExpectedVersion) { throw 'The update is no longer newer than the installed version.' }
    Add-AppxPackage -Path $PackagePath -DependencyPath $dependencies -ErrorAction Stop
    @{ Success = $true; Version = $ExpectedVersion } | ConvertTo-Json | Set-Content -LiteralPath $resultPath -Encoding UTF8
} catch {
    if ($ValidateOnly) { Write-Error $_; exit 1 }
    @{ Success = $false; Version = $ExpectedVersion; Message = 'The package update failed. The installed version was kept.' } |
        ConvertTo-Json | Set-Content -LiteralPath $resultPath -Encoding UTF8
    Add-Type -AssemblyName System.Windows.Forms
    [Windows.Forms.MessageBox]::Show('Ping could not apply the update. Please open Settings and try again.', 'Ping update') | Out-Null
} finally {
    if (-not $ValidateOnly) {
        $installed = Get-AppxPackage -Name $packageName
        if ($installed) { Start-Process explorer.exe -ArgumentList "shell:AppsFolder\$($installed.PackageFamilyName)!App" -WindowStyle Hidden }
    }
}
