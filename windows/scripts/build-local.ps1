[CmdletBinding()]
param(
    [ValidateSet('x64', 'ARM64')][string]$Platform = 'x64',
    [ValidateSet('Debug', 'Release')][string]$Configuration = 'Debug',
    [string]$DotnetPath,
    [string]$PackageOutputRoot,
    [switch]$Package,
    [switch]$UiSmoke,
    [switch]$UiRuntime
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
if ($UiSmoke -and $Package) { throw 'Diagnostic fixture builds must not be packaged for distribution.' }
if ($UiRuntime -and -not $UiSmoke) { throw 'UiRuntime requires the isolated UiSmoke diagnostic.' }
$windowsRoot = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path

if ([string]::IsNullOrWhiteSpace($DotnetPath)) {
    $localSdk = Join-Path $env:LOCALAPPDATA 'PingDevelopment\dotnet\dotnet.exe'
    $installedSdk = Get-Command dotnet -ErrorAction SilentlyContinue
    if (Test-Path -LiteralPath $localSdk) { $DotnetPath = $localSdk }
    elseif ($installedSdk) { $DotnetPath = $installedSdk.Source }
    else { throw '.NET 10 SDK is required. Supply -DotnetPath if it is installed outside PATH.' }
}

$vswhere = Join-Path ${env:ProgramFiles(x86)} 'Microsoft Visual Studio\Installer\vswhere.exe'
if (-not (Test-Path -LiteralPath $vswhere)) { throw 'Visual Studio C++ build tools are required.' }
$msbuild = & $vswhere -latest -products '*' -requires Microsoft.VisualStudio.Component.VC.Tools.x86.x64 -find 'MSBuild\Current\Bin\MSBuild.exe' | Select-Object -First 1
if ([string]::IsNullOrWhiteSpace($msbuild)) { throw 'Visual Studio v143 C++ build tools were not found.' }
# A trailing backslash escapes the closing quote in Windows PowerShell5.1 native arguments.
$vcTargets = [IO.Path]::GetFullPath((Join-Path (Split-Path -Parent $msbuild) '..\..\Microsoft\VC\v170')) + '/'
$targetFramework = 'net10.0-windows10.0.26100.0'
$rid = if ($Platform -eq 'ARM64') { 'win-arm64' } else { 'win-x64' }
$nativeRoot = Join-Path $windowsRoot 'src\Ping.Windows.NativeCapture'
$nativeOut = Join-Path $nativeRoot "bin\$Platform\$Configuration\$targetFramework\$rid\"
$nativeIntermediate = Join-Path $nativeRoot "obj\$Platform\$Configuration\"

function Invoke-Checked([string]$Executable, [string[]]$Arguments) {
    & $Executable @Arguments
    if ($LASTEXITCODE -ne 0) { throw "Build failed with exit code $LASTEXITCODE ($Executable)." }
}

# Full-framework C++ tasks cannot execute in dotnet MSBuild. Build native first,
# then compile managed projects with the .NET 10 SDK, including on older VS hosts.
Invoke-Checked $msbuild @(
    (Join-Path $nativeRoot 'Ping.Windows.NativeCapture.vcxproj'),
    "/p:Configuration=$Configuration", "/p:Platform=$Platform", "/p:OutDir=$nativeOut",
    "/p:IntDir=$nativeIntermediate", '/nologo', '/v:minimal'
)
Invoke-Checked $DotnetPath @(
    'build', (Join-Path $windowsRoot 'src\Ping.Windows.Core\Ping.Windows.Core.csproj'),
    "-p:Platform=$Platform", '-c', $Configuration, '--nologo', '-v:minimal'
)
$managedArguments = @(
    'build', (Join-Path $windowsRoot 'src\Ping.Windows.App\Ping.Windows.App.csproj'),
    "-p:Platform=$Platform", "-p:RuntimeIdentifier=$rid", '-c', $Configuration,
    '-p:BuildProjectReferences=false', "-p:VCTargetsPath=$vcTargets", '--nologo', '-v:minimal'
)
if ($Package) {
    $packageRoot = Join-Path $windowsRoot ("artifacts\local-{0}-{1}\" -f $Platform, [Guid]::NewGuid().ToString('N'))
    if (-not [string]::IsNullOrWhiteSpace($PackageOutputRoot)) {
        $packageRoot = [IO.Path]::GetFullPath($PackageOutputRoot).TrimEnd('\') + '/'
        $artifactRoot = [IO.Path]::GetFullPath((Join-Path $windowsRoot 'artifacts')).TrimEnd('\') + '\'
        if (-not $packageRoot.StartsWith($artifactRoot, [StringComparison]::OrdinalIgnoreCase)) { throw 'Package output must remain in Windows artifacts.' }
    }
    $managedArguments += @(
        '-p:GenerateAppxPackageOnBuild=true', '-p:UapAppxPackageBuildMode=SideloadOnly',
        '-p:AppxBundle=Never', '-p:AppxPackageSigningEnabled=false',
        '-p:AppxSymbolPackageEnabled=false', "-p:AppxPackageDir=$packageRoot"
    )
    $symbolTool = & $vswhere -latest -products '*' -find 'VC\Tools\MSVC\*\bin\Hostx64\x64\mspdbcmf.exe' | Select-Object -First 1
    if (-not [string]::IsNullOrWhiteSpace($symbolTool)) {
        $symbolTool32 = Join-Path (Split-Path -Parent (Split-Path -Parent $symbolTool)) 'x86\mspdbcmf.exe'
        $managedArguments += @("-p:PdbCmfx64ExeFullPath=$symbolTool", "-p:PdbCmfx86ExeFullPath=$symbolTool32")
    }
    Write-Warning 'This creates an unsigned validation MSIX. It is not an installable public release.'
}
if ($UiSmoke) { $managedArguments += '-p:PingUiSmoke=true' }
if ($UiRuntime) {
    # AppNotification registration in the SDK self-contained runtime lacks its
    # version resource DLL. Exercise the installed runtime in a separate QA build.
    $managedArguments += '-p:PingUiRuntime=true'
}
Invoke-Checked $DotnetPath $managedArguments
Write-Host "Built $Platform $Configuration."
if ($Package) { Write-Host "Validation packages: $packageRoot" }
