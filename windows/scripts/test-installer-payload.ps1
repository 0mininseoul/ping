[CmdletBinding()]
param([string]$FixtureSource)
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
if ([string]::IsNullOrWhiteSpace($FixtureSource)) { $FixtureSource = Join-Path $PSScriptRoot '..\..\web\public\downloads\windows' }
$fixtureRoot = Join-Path $PSScriptRoot ('..\artifacts\installer-fixture-' + [Guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $fixtureRoot | Out-Null
Copy-Item -LiteralPath (Join-Path $FixtureSource 'Ping-Windows-Sideload.cer') -Destination $fixtureRoot
Copy-Item -LiteralPath (Join-Path $FixtureSource 'Ping-Windows-v0.3.46-x64.msix') -Destination $fixtureRoot
$dependencyRoot = Join-Path $fixtureRoot 'Dependencies\x64'
New-Item -ItemType Directory -Path $dependencyRoot -Force | Out-Null
Copy-Item -LiteralPath (Join-Path $FixtureSource 'Dependencies\x64\Microsoft.WindowsAppRuntime.2.msix') -Destination $dependencyRoot
Set-Content -LiteralPath (Join-Path $fixtureRoot 'dependencies-x64.txt') -Encoding ascii -Value 'Dependencies/x64/Microsoft.WindowsAppRuntime.2.msix'
$installer = Join-Path $PSScriptRoot 'install-ping-windows.ps1'
function Invoke-Validation([string]$Version, [bool]$ExpectedSuccess, [string]$Label) {
    $log = Join-Path $fixtureRoot ($Label + '.log')
    $previousErrorAction = $ErrorActionPreference
    try {
        $ErrorActionPreference = 'Continue'
        & powershell.exe -NoProfile -NonInteractive -ExecutionPolicy Bypass -File $installer -Version $Version -Architecture x64 -PackageDirectory $fixtureRoot -CertificatePath (Join-Path $fixtureRoot 'Ping-Windows-Sideload.cer') -ValidateOnly *> $log
        $validationExitCode = $LASTEXITCODE
    } finally { $ErrorActionPreference = $previousErrorAction }
    $succeeded = $validationExitCode -eq 0
    if ($succeeded -ne $ExpectedSuccess) {
        Get-Content -LiteralPath $log -Tail 12 | Write-Output
        throw "$Label returned unexpected exit code $validationExitCode. See $log"
    }
    Write-Output "PASS $Label"
}
Invoke-Validation '0.3.46' $true 'signed-offline-payload'
Copy-Item -LiteralPath (Join-Path $fixtureRoot 'Ping-Windows-v0.3.46-x64.msix') -Destination (Join-Path $fixtureRoot 'Ping-Windows-v0.3.80-x64.msix')
Invoke-Validation '0.3.80' $false 'mismatched-package-version'
Set-Content -LiteralPath (Join-Path $fixtureRoot 'dependencies-x64.txt') -Encoding ascii -Value '../outside.msix'
Invoke-Validation '0.3.46' $false 'dependency-path-escape'
Write-Output "Fixture-only installer validation completed: $fixtureRoot"
