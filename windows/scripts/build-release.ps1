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
$solution = Join-Path $windowsRoot "PingWindows.sln"
$appProjectRoot = Join-Path $windowsRoot "src\Ping.Windows.App"
$distRoot = Join-Path $windowsRoot "dist"
$coreTestsProject = Join-Path $windowsRoot "tests\Ping.Windows.Core.Tests\Ping.Windows.Core.Tests.csproj"
$appTestsProject = Join-Path $windowsRoot "tests\Ping.Windows.App.Tests\Ping.Windows.App.Tests.csproj"

function Get-PingWindowsPackageVersion {
    $manifestPath = Join-Path $appProjectRoot "Package.appxmanifest"
    [xml]$manifest = Get-Content -Raw -LiteralPath $manifestPath
    $identityVersion = [string]$manifest.Package.Identity.Version
    $match = [regex]::Match($identityVersion, '^(?<version>\d+\.\d+\.\d+)\.0$')
    if (-not $match.Success) {
        throw "Package.appxmanifest Identity.Version must use major.minor.patch.0 format. Found $identityVersion."
    }

    return $match.Groups["version"].Value
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

function Resolve-SignTool {
    $command = Get-Command signtool.exe -ErrorAction SilentlyContinue
    if ($command) {
        return $command.Source
    }

    $kitBinRoot = Join-Path ${env:ProgramFiles(x86)} "Windows Kits\10\bin"
    if (Test-Path -LiteralPath $kitBinRoot) {
        foreach ($directory in Get-ChildItem -LiteralPath $kitBinRoot -Directory | Sort-Object Name -Descending) {
            $x64 = Join-Path $directory.FullName "x64\signtool.exe"
            if (Test-Path -LiteralPath $x64) {
                return $x64
            }

            $x86 = Join-Path $directory.FullName "x86\signtool.exe"
            if (Test-Path -LiteralPath $x86) {
                return $x86
            }
        }
    }

    throw "signtool.exe was not found. Install the Windows SDK signing tools."
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
    $Arguments.Add("/p:AppxPackageSigningEnabled=false")
    if (-not (Test-HasSigningCertificate)) {
        Write-Warning "No signing certificate was provided. Packages will be unsigned and are only useful for CI/build validation."
    }
}

function Test-HasSigningCertificate {
    return -not [string]::IsNullOrWhiteSpace($PackageCertificateThumbprint) -or
        -not [string]::IsNullOrWhiteSpace($PackageCertificateKeyFile)
}

function Sign-Package([string]$PackagePath) {
    if (-not (Test-HasSigningCertificate)) {
        return
    }

    $signTool = Resolve-SignTool
    $arguments = [System.Collections.Generic.List[string]]::new()
    $arguments.Add("sign")
    $arguments.Add("/fd")
    $arguments.Add("SHA256")

    if (-not [string]::IsNullOrWhiteSpace($PackageCertificateKeyFile)) {
        if (-not (Test-Path -LiteralPath $PackageCertificateKeyFile)) {
            throw "Signing certificate key file was not found: $PackageCertificateKeyFile"
        }

        $arguments.Add("/f")
        $arguments.Add($PackageCertificateKeyFile)
        if (-not [string]::IsNullOrWhiteSpace($PackageCertificatePassword)) {
            $arguments.Add("/p")
            $arguments.Add($PackageCertificatePassword)
        }
    } else {
        $arguments.Add("/sha1")
        $arguments.Add($PackageCertificateThumbprint)
    }

    $arguments.Add($PackagePath)
    Write-Host "Signing $(Split-Path -Leaf $PackagePath) with signtool.exe..."
    & $signTool @arguments
    if ($LASTEXITCODE -ne 0) {
        throw "signtool.exe failed for $PackagePath with exit code $LASTEXITCODE."
    }
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

$version = Get-PingWindowsPackageVersion
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
            $_.Name -like "*_$architectureManifestValue.msix" -and
            $_.FullName -notmatch '[\\/]Dependencies[\\/]'
        } |
        Sort-Object FullName |
        Select-Object -First 1

    if (-not $package) {
        throw "MSBuild completed but no .msix package was found for $targetPlatform."
    }

    $destination = Join-Path $distRoot "Ping-Windows-v$version-$architectureLabel.msix"
    Copy-Item -LiteralPath $package.FullName -Destination $destination -Force
    Sign-Package $destination

    Add-Type -AssemblyName System.IO.Compression.FileSystem
    $archive = [System.IO.Compression.ZipFile]::OpenRead($destination)
    try {
        $manifestEntry = $archive.Entries | Where-Object { $_.FullName -eq "AppxManifest.xml" } | Select-Object -First 1
        if (-not $manifestEntry) {
                throw "Package $destination does not contain AppxManifest.xml."
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

        Assert-PackageContainsNativeCaptureDll $archive $destination
    }
    finally {
        $archive.Dispose()
    }
    Write-Host "Wrote $destination"
}
