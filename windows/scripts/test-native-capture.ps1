[CmdletBinding()]
param([ValidateSet('Debug', 'Release')][string]$Configuration = 'Debug')

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$windowsRoot = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
$vswhere = Join-Path ${env:ProgramFiles(x86)} 'Microsoft Visual Studio\Installer\vswhere.exe'
$msbuild = & $vswhere -latest -products '*' -requires Microsoft.VisualStudio.Component.VC.Tools.x86.x64 -find 'MSBuild\Current\Bin\MSBuild.exe' | Select-Object -First 1
if ([string]::IsNullOrWhiteSpace($msbuild)) { throw 'Visual Studio v143 C++ build tools are required.' }
$output = Join-Path $windowsRoot ('artifacts\native-tests-' + [Guid]::NewGuid().ToString('N'))
$project = Join-Path $windowsRoot 'tests\Ping.Windows.NativeCapture.Tests\Ping.Windows.NativeCapture.Tests.vcxproj'
& $msbuild $project "/p:Configuration=$Configuration" '/p:Platform=x64' "/p:OutDir=$output\" "/p:IntDir=$output\obj\" '/nologo' '/v:minimal'
if ($LASTEXITCODE -ne 0) { throw "Native test build failed ($LASTEXITCODE)." }
& (Join-Path $output 'Ping.Windows.NativeCapture.Tests.exe') $output
if ($LASTEXITCODE -ne 0) { throw "Native synthetic checks failed ($LASTEXITCODE). Output: $output" }
Write-Host "Native test artifacts: $output"
