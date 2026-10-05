[CmdletBinding()]
param([switch]$SkipBuild, [switch]$Redirection)
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$windowsRoot = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
if (-not $SkipBuild) { & (Join-Path $PSScriptRoot 'build-local.ps1') -UiSmoke -UiRuntime }
$executable = Join-Path $windowsRoot 'artifacts/ui-runtime/bin/x64/Debug/net10.0-windows10.0.26100.0/win-x64/Ping.Windows.App.exe'
if (-not (Test-Path -LiteralPath $executable)) { throw 'Build the isolated runtime diagnostic first.' }
$output = Join-Path $windowsRoot ('artifacts/notification-startup-' + [guid]::NewGuid().ToString('N'))
$arguments = if ($Redirection) { @('--ui-notification-redirection-output', ('"' + $output + '"')) } else { @('--ui-notification-startup-output', ('"' + $output + '"'), '----AppNotificationActivated:') }
$process = Start-Process -FilePath $executable -ArgumentList $arguments -WindowStyle Hidden -PassThru
if (-not $process.WaitForExit(45000)) {
    Stop-Process -Id $process.Id -ErrorAction SilentlyContinue
    throw "Notification startup diagnostic timed out: $output"
}
$resultPath = Join-Path $output 'result.json'
New-Item -ItemType Directory -Path $output -Force | Out-Null
@{ProcessExitCode=$process.ExitCode;ResultFilePresent=(Test-Path -LiteralPath $resultPath)} | ConvertTo-Json |
    Set-Content -LiteralPath (Join-Path $output 'process-exit.json')
if (-not (Test-Path -LiteralPath $resultPath)) { throw "Notification startup diagnostic exited without a result: $output" }
$result = Get-Content -LiteralPath $resultPath -Raw | ConvertFrom-Json
if ($process.ExitCode -ne 0 -or -not $result.Success) { throw "Notification startup diagnostic failed: $($result.Error). Evidence: $output" }
Write-Host "PASS: $($result.Checks.Count) native notification startup checks. Evidence: $output"
