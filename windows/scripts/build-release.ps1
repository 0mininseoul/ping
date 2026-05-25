[CmdletBinding()]
param(
    [ValidateSet("x64", "ARM64")]
    [string[]]$Platform = @("x64", "ARM64"),
    [string]$Configuration = "Release",
    [switch]$SkipTests,
    [string]$PackageCertificateThumbprint = $env:PING_WINDOWS_CERT_THUMBPRINT,
    [string]$PackageCertificateKeyFile = $env:PING_WINDOWS_CERT_PATH,
    [string]$PackageCertificatePassword = $env:PING_WINDOWS_CERT_PASSWORD
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$windowsRoot = Resolve-Path (Join-Path $PSScriptRoot "..")
$repoRoot = Resolve-Path (Join-Path $windowsRoot "..")
$solution = Join-Path $windowsRoot "PingWindows.sln"
$appProjectRoot = Join-Path $windowsRoot "src\Ping.Windows.App"
$distRoot = Join-Path $windowsRoot "dist"
$coreTestsProject = Join-Path $windowsRoot "tests\Ping.Windows.Core.Tests\Ping.Windows.Core.Tests.csproj"
$appTestsProject = Join-Path $windowsRoot "tests\Ping.Windows.App.Tests\Ping.Windows.App.Tests.csproj"

function Get-PingMarketingVersion {
    $projectYml = Join-Path $repoRoot "project.yml"
    $contents = Get-Content -Raw -LiteralPath $projectYml
    $match = [regex]::Match($contents, 'MARKETING_VERSION:\s*"([^"]+)"')
    if (-not $match.Success) {
        throw "Could not read MARKETING_VERSION from project.yml."
    }

    return $match.Groups[1].Value
}

function Assert-PackageManifestVersion([string]$MarketingVersion) {
    $manifestPath = Join-Path $appProjectRoot "Package.appxmanifest"
    [xml]$manifest = Get-Content -Raw -LiteralPath $manifestPath
    $expectedVersion = "$MarketingVersion.0"
    $actualVersion = $manifest.Package.Identity.Version
    if ($actualVersion -ne $expectedVersion) {
        throw "Package.appxmanifest version $actualVersion does not match project.yml MARKETING_VERSION $MarketingVersion. Expected $expectedVersion."
    }
}

function Resolve-MSBuild {
    $vswhere = Join-Path ${env:ProgramFiles(x86)} "Microsoft Visual Studio\Installer\vswhere.exe"
    if (Test-Path -LiteralPath $vswhere) {
        $path = & $vswhere -latest -products * -requires Microsoft.Component.MSBuild -find "MSBuild\Current\Bin\MSBuild.exe" |
            Select-Object -First 1
        if (-not [string]::IsNullOrWhiteSpace($path)) {
            return $path
        }
    }

    $command = Get-Command msbuild.exe -ErrorAction SilentlyContinue
    if ($command) {
        return $command.Source
    }

    throw "MSBuild was not found. Install Visual Studio with .NET desktop, C++ desktop, and Windows App SDK tooling."
}

function Get-PackageArchitectureLabel([string]$TargetPlatform) {
    if ($TargetPlatform -eq "ARM64") {
        return "arm64"
    }

    return "x64"
}

function Get-PackageArchitectureManifestValue([string]$TargetPlatform) {
    if ($TargetPlatform -eq "ARM64") {
        return "arm64"
    }

    return "x64"
}

function Add-SigningProperties([System.Collections.Generic.List[string]]$Arguments) {
    if (-not [string]::IsNullOrWhiteSpace($PackageCertificateThumbprint)) {
        $Arguments.Add("/p:AppxPackageSigningEnabled=true")
        $Arguments.Add("/p:PackageCertificateThumbprint=$PackageCertificateThumbprint")
        return
    }

    if (-not [string]::IsNullOrWhiteSpace($PackageCertificateKeyFile)) {
        $Arguments.Add("/p:AppxPackageSigningEnabled=true")
        $Arguments.Add("/p:PackageCertificateKeyFile=$PackageCertificateKeyFile")
        if (-not [string]::IsNullOrWhiteSpace($PackageCertificatePassword)) {
            $Arguments.Add("/p:PackageCertificatePassword=$PackageCertificatePassword")
        }
        return
    }

    Write-Warning "No signing certificate was provided. Packages will be unsigned and are only useful for CI/build validation."
    $Arguments.Add("/p:AppxPackageSigningEnabled=false")
}

function Assert-PackageContainsNativeCaptureDll($Archive, [string]$PackagePath) {
    $nativeDllEntry = $Archive.Entries |
        Where-Object { $_.Name -eq "Ping.Windows.NativeCapture.dll" } |
        Select-Object -First 1

    if (-not $nativeDllEntry) {
        throw "Package $PackagePath does not contain Ping.Windows.NativeCapture.dll."
    }

    if ($nativeDllEntry.Length -le 0) {
        throw "Package $PackagePath contains an empty Ping.Windows.NativeCapture.dll."
    }
}

$version = Get-PingMarketingVersion
Assert-PackageManifestVersion $version
$msbuild = Resolve-MSBuild
New-Item -ItemType Directory -Force -Path $distRoot | Out-Null

if (-not $SkipTests) {
    dotnet test $coreTestsProject -c $Configuration
    if ($LASTEXITCODE -ne 0) {
        throw "Core tests failed with exit code $LASTEXITCODE."
    }

    dotnet test $appTestsProject -c $Configuration
    if ($LASTEXITCODE -ne 0) {
        throw "App tests failed with exit code $LASTEXITCODE."
    }
}

foreach ($targetPlatform in $Platform) {
    $architectureLabel = Get-PackageArchitectureLabel $targetPlatform
    $architectureManifestValue = Get-PackageArchitectureManifestValue $targetPlatform
    $packageOutputRoot = Join-Path $windowsRoot "artifacts\appx\$targetPlatform"
    Remove-Item -Recurse -Force -LiteralPath $packageOutputRoot -ErrorAction SilentlyContinue
    New-Item -ItemType Directory -Force -Path $packageOutputRoot | Out-Null

    $arguments = [System.Collections.Generic.List[string]]::new()
    $arguments.Add($solution)
    $arguments.Add("/restore")
    $arguments.Add("/m:1")
    $arguments.Add("/p:Configuration=$Configuration")
    $arguments.Add("/p:Platform=$targetPlatform")
    $arguments.Add("/p:GenerateAppxPackageOnBuild=true")
    $arguments.Add("/p:UapAppxPackageBuildMode=SideloadOnly")
    $arguments.Add("/p:AppxBundle=Never")
    $arguments.Add("/p:AppxPackageDir=$packageOutputRoot\")
    Add-SigningProperties $arguments

    Write-Host "Building Ping Windows $version for $targetPlatform..."
    & $msbuild @arguments
    if ($LASTEXITCODE -ne 0) {
        throw "MSBuild failed for $targetPlatform with exit code $LASTEXITCODE."
    }

    $package = Get-ChildItem -Path $packageOutputRoot -Recurse -Filter "*.msix" |
        Where-Object {
            $name = $_.BaseName
            $name -like "YoungminPark.PingWindows_*" -and
            $name -like "*_$architectureManifestValue*"
        } |
        Sort-Object FullName |
        Select-Object -First 1

    if (-not $package) {
        throw "MSBuild completed but no .msix package was found for $targetPlatform."
    }

    Add-Type -AssemblyName System.IO.Compression.FileSystem
    $archive = [System.IO.Compression.ZipFile]::OpenRead($package.FullName)
    try {
        $manifestEntry = $archive.Entries | Where-Object { $_.FullName -eq "AppxManifest.xml" } | Select-Object -First 1
        if (-not $manifestEntry) {
            throw "Package $($package.FullName) does not contain AppxManifest.xml."
        }

        $stream = $manifestEntry.Open()
        try {
            $reader = [System.IO.StreamReader]::new($stream)
            try {
                [xml]$packageManifest = $reader.ReadToEnd()
            }
            finally {
                $reader.Dispose()
            }
        }
        finally {
            $stream.Dispose()
        }

        $identity = $packageManifest.Package.Identity
        if ($identity.Name -ne "YoungminPark.PingWindows") {
            throw "Package identity $($identity.Name) is not YoungminPark.PingWindows."
        }

        if ($identity.Version -ne "$version.0") {
            throw "Package version $($identity.Version) does not match $version.0."
        }

        if ($identity.ProcessorArchitecture -ne $architectureManifestValue) {
            throw "Package architecture $($identity.ProcessorArchitecture) does not match $architectureManifestValue."
        }

        Assert-PackageContainsNativeCaptureDll $archive $package.FullName
    }
    finally {
        $archive.Dispose()
    }

    $destination = Join-Path $distRoot "Ping-Windows-v$version-$architectureLabel.msix"
    Copy-Item -LiteralPath $package.FullName -Destination $destination -Force
    Write-Host "Wrote $destination"
}
