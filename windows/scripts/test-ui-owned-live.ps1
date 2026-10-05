[CmdletBinding()]
param(
    [Parameter(Mandatory)][string]$OwnedSessionsDirectory,
    [Parameter(Mandatory)][string]$FixturesDirectory,
    [Parameter(Mandatory)][ValidatePattern('^\\\\\.\\DISPLAY[1-9][0-9]*$')][string]$MonitorDeviceName,
    [switch]$SkipBuild,
    [switch]$Runtime
)
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$windowsRoot = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
$artifactRoot = [IO.Path]::GetFullPath((Join-Path $windowsRoot 'artifacts')).TrimEnd('\') + '\'
$sessions = (Resolve-Path -LiteralPath $OwnedSessionsDirectory).Path
$fixtures = (Resolve-Path -LiteralPath $FixturesDirectory).Path
if (-not $sessions.StartsWith($artifactRoot, [StringComparison]::OrdinalIgnoreCase) -or -not $fixtures.StartsWith($artifactRoot, [StringComparison]::OrdinalIgnoreCase)) {
    throw 'Use existing owned QA sessions and fixtures under windows/artifacts, never user account directories.'
}
foreach ($name in @('a', 'b')) {
    if (-not (Test-Path -LiteralPath (Join-Path $sessions "$name\SupabaseSession.json") -PathType Leaf)) { throw 'Both existing owned sessions are required.' }
}
foreach ($name in @('owned-photo.png', 'owned-face-source.mp4')) {
    if (-not (Test-Path -LiteralPath (Join-Path $fixtures $name) -PathType Leaf)) { throw 'Owned photo and three-second video fixtures are required.' }
}
. (Join-Path $PSScriptRoot 'ping-user-data.ps1')
$package = Get-AppxPackage YoungminPark.PingWindows
if ($null -eq $package) { throw 'Install a Ping candidate to supply the pinned runtime configuration.' }
$paths = Get-PingDataPaths $env:LOCALAPPDATA $package.PackageFamilyName
$sources = @($paths.Physical, $paths.Virtual, $paths.Preserved)
function Get-OwnedQaUserSnapshot {
    @($sources | ForEach-Object {
        $directory = $_
        foreach ($name in (Get-PingRetainedFileNames @($directory))) {
            $file = Join-Path $directory $name
            if (Test-Path -LiteralPath $file -PathType Leaf) {
                [pscustomobject]@{ Path = $file; Hash = (Get-FileHash -LiteralPath $file -Algorithm SHA256).Hash; Length = (Get-Item -LiteralPath $file).Length }
            }
        }
    })
}
if (-not $SkipBuild) { & (Join-Path $PSScriptRoot 'build-local.ps1') -UiSmoke -UiRuntime:$Runtime }
$buildDirectory = if ($Runtime) { 'ui-runtime' } else { 'ui-smoke' }
$executable = Join-Path $windowsRoot "artifacts\$buildDirectory\bin\x64\Debug\net10.0-windows10.0.26100.0\win-x64\Ping.Windows.App.exe"
if (-not (Test-Path -LiteralPath $executable)) { throw 'Build the isolated native diagnostic first.' }
$output = Join-Path $windowsRoot ('artifacts\owned-native-' + [Guid]::NewGuid().ToString('N'))
$null = New-Item -ItemType Directory -Path $output
$before = @(Get-OwnedQaUserSnapshot)
ConvertTo-Json -InputObject $before -Depth 4 | Set-Content -LiteralPath "$output\user-data-before.json"
$config = Join-Path $package.InstallLocation 'Supabase.json'
$previousDisplay = $env:PING_UI_SMOKE_DISPLAY
try {
    $env:PING_UI_SMOKE_DISPLAY = $MonitorDeviceName
    $route = if ($Runtime) { '--ui-owned-runtime' } else { '--ui-owned-live' }
    $arguments = '{0} "{1}" "{2}" "{3}" "{4}"' -f $route, $output, $config, $sessions, $fixtures
    $process = Start-Process -FilePath $executable -ArgumentList $arguments -PassThru -WindowStyle Hidden
} finally { $env:PING_UI_SMOKE_DISPLAY = $previousDisplay }
$output | Set-Content -LiteralPath (Join-Path $windowsRoot 'artifacts\current-owned-native.txt')
while (-not $process.WaitForExit(1000)) { }
$after = @(Get-OwnedQaUserSnapshot)
$unchanged = $before.Count -eq $after.Count
foreach ($file in $before) {
    $row = @($after | Where-Object Path -eq $file.Path)
    if ($row.Count -ne 1 -or $row[0].Hash -ne $file.Hash -or $row[0].Length -ne $file.Length) { $unchanged = $false }
}
[pscustomobject]@{ UserDataUnchanged = $unchanged; RetainedFiles = $after.Count; ProcessExitCode = $process.ExitCode } |
    ConvertTo-Json | Set-Content -LiteralPath "$output\user-data-verification.json"
if (-not (Test-Path -LiteralPath "$output\result.json")) { throw "Native owned QA exited without a result; inspect $output and repair only its recorded owned room." }
$result = Get-Content -LiteralPath "$output\result.json" -Raw | ConvertFrom-Json
if (-not $unchanged -or -not $result.Success) { throw "Native owned QA failed; inspect $output. UserDataUnchanged=$unchanged" }
if ($result.PSObject.Properties.Name -contains 'Limitations') {
    foreach ($limitation in $result.Limitations) { Write-Host "UNVERIFIED: $limitation" }
}
Write-Host "PASS: $($result.Checks.Count) native owned live checks, $($after.Count) retained user files unchanged. Results: $output"
