[CmdletBinding()]
param([switch]$SkipBuild)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$windowsRoot = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
if (-not $SkipBuild) { & (Join-Path $PSScriptRoot 'build-local.ps1') -UiSmoke -UiRuntime }
$executable = Join-Path $windowsRoot 'artifacts/ui-runtime/bin/x64/Debug/net10.0-windows10.0.26100.0/win-x64/Ping.Windows.App.exe'
if (-not (Test-Path -LiteralPath $executable)) { throw 'Build the isolated runtime diagnostic first.' }
$output = Join-Path $windowsRoot ('artifacts/activation-' + [guid]::NewGuid().ToString('N'))
$process = Start-Process -FilePath $executable -ArgumentList @('--ui-activation-output', ('"' + $output + '"')) -WindowStyle Hidden -PassThru
if (-not $process.WaitForExit(45000)) {
    Stop-Process -Id $process.Id -ErrorAction SilentlyContinue
    throw "Activation diagnostic timed out: $output"
}
$resultPath = Join-Path $output 'result.json'
if (-not (Test-Path -LiteralPath $resultPath)) { throw "Activation diagnostic exited without a result: $output" }
$result = Get-Content -LiteralPath $resultPath -Raw | ConvertFrom-Json
if ($process.ExitCode -ne 0 -or -not $result.Success) { throw "Activation diagnostic failed: $($result.Error). Evidence: $output" }
Write-Host "PASS: $($result.Checks.Count) native activation checks. Evidence: $output"
