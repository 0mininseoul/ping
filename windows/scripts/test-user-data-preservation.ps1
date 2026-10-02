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
$snapshot = Save-PingUserData -LocalAppDataRoot $fixtureRoot -PackageFamilyName $family
if ((Get-Content -Raw -LiteralPath (Join-Path $snapshot 'SupabaseSession.json')).Trim() -ne 'fixture-latest-account') { throw 'Virtualized account did not take priority.' }
if (Test-Path -LiteralPath (Join-Path $snapshot 'recording.tmp')) { throw 'Temporary recording was copied.' }
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
Write-Output "Fixture-only data preservation completed: $fixtureRoot"
