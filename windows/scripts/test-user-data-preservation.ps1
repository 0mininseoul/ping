[CmdletBinding()]
param()
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'ping-user-data.ps1')
$fixtureRoot = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot ('..\artifacts\data-fixture-' + [Guid]::NewGuid().ToString('N'))))
$family = 'YoungminPark.PingWindows_fixture'
$physical = Join-Path $fixtureRoot 'Ping'
$virtual = Join-Path $fixtureRoot "Packages\$family\LocalCache\Local\Ping"
New-Item -ItemType Directory -Path $physical,$virtual -Force | Out-Null
Set-Content -LiteralPath (Join-Path $physical 'SupabaseSession.json') -Value 'fixture-old-account'
Set-Content -LiteralPath (Join-Path $virtual 'SupabaseSession.json') -Value 'fixture-latest-account'
Set-Content -LiteralPath (Join-Path $physical 'UserPreferences.json') -Value 'fixture-preferences'
Set-Content -LiteralPath (Join-Path $virtual 'recording.tmp') -Value 'fixture-temporary'
$scopedLedger = 'NotifiedChatIds-' + ('a' * 64) + '.json'
Set-Content -LiteralPath (Join-Path $virtual $scopedLedger) -Value 'fixture-scoped-ledger'
$snapshot = Save-PingUserData -LocalAppDataRoot $fixtureRoot -PackageFamilyName $family
if ((Get-Content -Raw -LiteralPath (Join-Path $snapshot 'SupabaseSession.json')).Trim() -ne 'fixture-latest-account') { throw 'Virtualized account did not take priority.' }
if (Test-Path -LiteralPath (Join-Path $snapshot 'recording.tmp')) { throw 'Temporary recording was copied.' }
if (-not (Test-Path -LiteralPath (Join-Path $snapshot $scopedLedger))) { throw 'Account notification ledger was not preserved.' }
Write-Output 'PASS latest virtualized identity and physical preferences retained; temporary files excluded'
Restore-PingUserData -LocalAppDataRoot $fixtureRoot -PackageFamilyName $family
if ((Get-Content -Raw -LiteralPath (Join-Path $physical 'SupabaseSession.json')).Trim() -ne 'fixture-old-account') { throw 'Reinstallation replaced an existing account.' }
Write-Output 'PASS reinstall keeps an existing account'
Restore-PingUserData -LocalAppDataRoot $fixtureRoot -PackageFamilyName $family -OverwriteExisting
if ((Get-Content -Raw -LiteralPath (Join-Path $physical 'SupabaseSession.json')).Trim() -ne 'fixture-latest-account') { throw 'Uninstall preservation failed.' }
if ((Get-Content -Raw -LiteralPath (Join-Path $physical 'UserPreferences.json')).Trim() -ne 'fixture-preferences') { throw 'Preferences lost.' }
Write-Output 'PASS removal preserves latest data outside the MSIX package'
$neighbor = Join-Path $fixtureRoot 'OtherApp'
New-Item -ItemType Directory -Path $neighbor | Out-Null
Set-Content -LiteralPath (Join-Path $neighbor 'keep.txt') -Value 'fixture-neighbor'
Remove-PingUserData -LocalAppDataRoot $fixtureRoot -PackageFamilyName $family
if ((Test-Path -LiteralPath $physical) -or (Test-Path -LiteralPath $virtual) -or (Test-Path -LiteralPath (Join-Path $fixtureRoot "PingWindows\PreservedData\$family"))) { throw 'Explicit data deletion failed.' }
if (-not (Test-Path -LiteralPath (Join-Path $neighbor 'keep.txt'))) { throw 'Unrelated data changed.' }
Write-Output 'PASS explicit deletion is limited to Ping data'
try { Save-PingUserData -LocalAppDataRoot $fixtureRoot -PackageFamilyName '..\OtherApp'; throw 'Unsafe package family accepted.' }
catch { if ($_.Exception.Message -eq 'Unsafe package family accepted.') { throw }; if ($_.Exception.Message -notmatch 'Invalid Ping package family') { throw } }
Write-Output 'PASS package family traversal rejected'

New-Item -ItemType Directory -Path $physical -Force | Out-Null
Set-Content -LiteralPath (Join-Path $physical 'SupabaseSession.json') -Value 'fixture-legacy-account'
Set-Content -LiteralPath (Join-Path $physical 'SupabaseSession.json.bak') -Value 'fixture-legacy-backup'
Set-Content -LiteralPath (Join-Path $physical 'UserPreferences.json') -Value 'fixture-legacy-preferences'
Set-Content -LiteralPath (Join-Path $physical 'MessengerWindowPlacement.json') -Value 'fixture-display3-placement'
Initialize-PingPackagedData -LocalAppDataRoot $fixtureRoot -PackageFamilyName $family
foreach ($name in @('SupabaseSession.json','SupabaseSession.json.bak','UserPreferences.json','MessengerWindowPlacement.json')) {
    if (-not (Test-Path -LiteralPath (Join-Path $virtual $name)) -or
        (Get-FileHash -LiteralPath (Join-Path $physical $name)).Hash -ne (Get-FileHash -LiteralPath (Join-Path $virtual $name)).Hash) {
        throw 'Packaged first launch cannot read the retained legacy account and preferences.'
    }
}
Write-Output 'PASS first packaged launch receives byte-identical legacy account and preferences'

Set-Content -LiteralPath (Join-Path $virtual 'SupabaseSession.json') -Value 'fixture-current-package-account'
Remove-Item -LiteralPath (Join-Path $virtual 'SupabaseSession.json.bak')
Set-Content -LiteralPath (Join-Path $virtual 'UserPreferences.json') -Value 'fixture-current-package-preferences'
Initialize-PingPackagedData -LocalAppDataRoot $fixtureRoot -PackageFamilyName $family
if ((Get-Content -LiteralPath (Join-Path $virtual 'SupabaseSession.json') -Raw).Trim() -ne 'fixture-current-package-account' -or
    (Test-Path -LiteralPath (Join-Path $virtual 'SupabaseSession.json.bak')) -or
    (Get-Content -LiteralPath (Join-Path $virtual 'UserPreferences.json') -Raw).Trim() -ne 'fixture-current-package-preferences') {
    throw 'Package account or preferences were overwritten or mixed with a legacy account backup.'
}
Write-Output 'PASS existing package identity and preferences take priority; unrelated backup is not mixed'

Remove-Item -LiteralPath (Join-Path $virtual 'SupabaseSession.json')
Set-Content -LiteralPath (Join-Path $virtual 'SupabaseSession.json.bak') -Value 'fixture-package-backup-account'
Initialize-PingPackagedData -LocalAppDataRoot $fixtureRoot -PackageFamilyName $family
if ((Get-Content -LiteralPath (Join-Path $virtual 'SupabaseSession.json') -Raw).Trim() -ne 'fixture-package-backup-account') { throw 'Package backup identity was replaced with a legacy identity.' }
Write-Output 'PASS backup-only package identity is restored before legacy import'

$null = Save-PingUserData -LocalAppDataRoot $fixtureRoot -PackageFamilyName $family
Remove-Item -LiteralPath (Join-Path $physical 'SupabaseSession.json')
Remove-Item -LiteralPath (Join-Path $physical 'SupabaseSession.json.bak')
Assert-PingDataPath $virtual $fixtureRoot
Remove-Item -LiteralPath $virtual -Recurse
Restore-PingUserData -LocalAppDataRoot $fixtureRoot -PackageFamilyName $family
Initialize-PingPackagedData -LocalAppDataRoot $fixtureRoot -PackageFamilyName $family
if ((Get-Content -LiteralPath (Join-Path $virtual 'SupabaseSession.json') -Raw).Trim() -ne 'fixture-package-backup-account') { throw 'Reinstalled runtime cannot read preserved package identity.' }
Write-Output 'PASS reinstall restores preserved identity into the runtime package path'

Set-Content -LiteralPath (Join-Path $physical 'SupabaseSession.json') -Value 'fixture-previous-account'
Set-Content -LiteralPath (Join-Path $physical 'SupabaseSession.json.bak') -Value 'fixture-previous-backup'
Set-Content -LiteralPath (Join-Path $virtual 'SupabaseSession.json') -Value 'fixture-active-account'
Remove-Item -LiteralPath (Join-Path $virtual 'SupabaseSession.json.bak')
$snapshot = Save-PingUserData -LocalAppDataRoot $fixtureRoot -PackageFamilyName $family
if (Test-Path -LiteralPath (Join-Path $snapshot 'SupabaseSession.json.bak')) { throw 'Preservation mixed the active package account with a previous physical backup.' }
Assert-PingDataPath $virtual $fixtureRoot
Remove-Item -LiteralPath $virtual -Recurse
Restore-PingUserData -LocalAppDataRoot $fixtureRoot -PackageFamilyName $family -OverwriteExisting
Initialize-PingPackagedData -LocalAppDataRoot $fixtureRoot -PackageFamilyName $family
if ((Get-Content -LiteralPath (Join-Path $virtual 'SupabaseSession.json') -Raw).Trim() -ne 'fixture-active-account' -or
    (Test-Path -LiteralPath (Join-Path $physical 'SupabaseSession.json.bak')) -or
    (Test-Path -LiteralPath (Join-Path $virtual 'SupabaseSession.json.bak'))) { throw 'Uninstall and reinstall retained a previous account backup.' }
Write-Output 'PASS uninstall and reinstall preserve one account group without a stale backup'

Remove-Item -LiteralPath (Join-Path $virtual 'SupabaseSession.json')
Set-Content -LiteralPath (Join-Path $virtual 'SupabaseSession.json.bak') -Value 'fixture-backup-only-account'
$snapshot = Save-PingUserData -LocalAppDataRoot $fixtureRoot -PackageFamilyName $family
if ((Get-Content -LiteralPath (Join-Path $snapshot 'SupabaseSession.json') -Raw).Trim() -ne 'fixture-backup-only-account' -or
    (Get-Content -LiteralPath (Join-Path $snapshot 'SupabaseSession.json.bak') -Raw).Trim() -ne 'fixture-backup-only-account') { throw 'Backup-only package identity was mixed with a physical identity.' }
Write-Output 'PASS backup-only package preservation keeps primary and backup in the same account group'

Assert-PingDataPath $virtual $fixtureRoot
Remove-Item -LiteralPath $virtual -Recurse
Set-Content -LiteralPath (Join-Path $physical 'SupabaseSession.json') -Value 'fixture-existing-account'
Restore-PingUserData -LocalAppDataRoot $fixtureRoot -PackageFamilyName $family
if ((Get-Content -LiteralPath (Join-Path $physical 'SupabaseSession.json') -Raw).Trim() -ne 'fixture-existing-account' -or
    (Test-Path -LiteralPath (Join-Path $physical 'SupabaseSession.json.bak'))) { throw 'Non-overwriting restoration mixed a preserved backup into an existing account.' }
Write-Output 'PASS non-overwriting restoration preserves the complete existing account group'
Write-Output "Fixture-only data preservation completed: $fixtureRoot"
