[CmdletBinding()]
param(
    [string]$Version,
    [ValidateSet("x64", "arm64")]
    [string]$Architecture,
    [string]$PackageDirectory = $PSScriptRoot,
    [string]$PackageBaseUrl,
    [string]$CertificatePath = (Join-Path $PSScriptRoot "Ping-Windows-Sideload.cer"),
    [switch]$NoLaunch,
    [switch]$CreateDesktopShortcut,
    [switch]$CreateStartMenuShortcut,
    [switch]$AddToStartup,
    [string]$IconPath,
    [switch]$AllowUnsigned
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$packageName = "YoungminPark.PingWindows"

function Test-Administrator {
    $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = [Security.Principal.WindowsPrincipal]::new($identity)
    return $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

function Quote-Argument([string]$Value) {
    return '"' + ($Value -replace '"', '\"') + '"'
}

function Restart-Elevated {
    $hostPath = (Get-Process -Id $PID).Path
    if ([string]::IsNullOrWhiteSpace($hostPath)) {
        $hostPath = "powershell.exe"
    }

    $arguments = [System.Collections.Generic.List[string]]::new()
    $arguments.Add("-NoProfile")
    $arguments.Add("-ExecutionPolicy")
    $arguments.Add("Bypass")
    $arguments.Add("-File")
    $arguments.Add((Quote-Argument $PSCommandPath))
    if (-not [string]::IsNullOrWhiteSpace($Version)) {
        $arguments.Add("-Version")
        $arguments.Add((Quote-Argument $Version))
    }
    if (-not [string]::IsNullOrWhiteSpace($Architecture)) {
        $arguments.Add("-Architecture")
        $arguments.Add($Architecture)
    }
    $arguments.Add("-PackageDirectory")
    $arguments.Add((Quote-Argument $PackageDirectory))
    if (-not [string]::IsNullOrWhiteSpace($PackageBaseUrl)) {
        $arguments.Add("-PackageBaseUrl")
        $arguments.Add((Quote-Argument $PackageBaseUrl))
    }
    $arguments.Add("-CertificatePath")
    $arguments.Add((Quote-Argument $CertificatePath))
    if ($CreateDesktopShortcut) {
        $arguments.Add("-CreateDesktopShortcut")
    }
    if ($CreateStartMenuShortcut) {
        $arguments.Add("-CreateStartMenuShortcut")
    }
    if ($AddToStartup) {
        $arguments.Add("-AddToStartup")
    }
    if (-not [string]::IsNullOrWhiteSpace($IconPath)) {
        $arguments.Add("-IconPath")
        $arguments.Add((Quote-Argument $IconPath))
    }
    if ($NoLaunch) {
        $arguments.Add("-NoLaunch")
    }
    if ($AllowUnsigned) {
        $arguments.Add("-AllowUnsigned")
    }

    Start-Process -FilePath $hostPath -Verb RunAs -ArgumentList $arguments
}

function Resolve-Architecture {
    if (-not [string]::IsNullOrWhiteSpace($Architecture)) {
        return $Architecture
    }

    if ([System.Runtime.InteropServices.RuntimeInformation]::ProcessArchitecture -eq [System.Runtime.InteropServices.Architecture]::Arm64) {
        return "arm64"
    }

    return "x64"
}

function Get-CurrentWindowsBuild {
    try {
        $currentVersion = Get-ItemProperty -LiteralPath "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion"
        $buildText = [string]$currentVersion.CurrentBuildNumber
        if (-not [string]::IsNullOrWhiteSpace($buildText)) {
            return [int]$buildText
        }
    }
    catch {
        Write-Warning "Could not read Windows build from registry. Falling back to Environment.OSVersion. $($_.Exception.Message)"
    }

    return [Environment]::OSVersion.Version.Build
}

function Assert-SupportedWindowsVersion {
    $minimumBuild = 26100
    $build = Get-CurrentWindowsBuild
    if ($build -lt $minimumBuild) {
        throw "Ping for Windows requires Windows 11 24H2 or newer (build $minimumBuild+). This PC reports build $build. Please update Windows before installing Ping."
    }
}

function Resolve-Version([string]$TargetArchitecture) {
    if (-not [string]::IsNullOrWhiteSpace($Version)) {
        return $Version
    }

    if (-not [string]::IsNullOrWhiteSpace($PackageBaseUrl)) {
        throw "Version is required when installing from PackageBaseUrl."
    }

    $candidate = Get-ChildItem -LiteralPath $PackageDirectory -Filter "Ping-Windows-v*-$TargetArchitecture.msix" |
        Sort-Object Name -Descending |
        Select-Object -First 1
    if (-not $candidate) {
        throw "Could not find a Ping Windows MSIX for $TargetArchitecture in $PackageDirectory."
    }

    if ($candidate.Name -notmatch '^Ping-Windows-v(?<version>.+)-[^-]+\.msix$') {
        throw "Could not infer version from $($candidate.Name)."
    }

    return $Matches.version
}

function Join-PackageUrl([string]$BaseUrl, [string]$FileName) {
    return $BaseUrl.TrimEnd([char[]]"/") + "/" + $FileName
}

function Download-PackageIfNeeded([string]$PackagePath, [string]$PackageFileName) {
    if (Test-Path -LiteralPath $PackagePath) {
        return
    }

    if ([string]::IsNullOrWhiteSpace($PackageBaseUrl)) {
        throw "Missing MSIX package: $PackagePath"
    }

    New-Item -ItemType Directory -Force -Path $PackageDirectory | Out-Null
    $packageUrl = Join-PackageUrl $PackageBaseUrl $PackageFileName
    Write-Host "Downloading $PackageFileName..."
    Invoke-WebRequest -Uri $packageUrl -OutFile $PackagePath -UseBasicParsing
}

function Resolve-DependencyManifestLines([string]$TargetArchitecture) {
    $manifestFileName = "dependencies-$TargetArchitecture.txt"
    $localManifestPath = Join-Path $PackageDirectory $manifestFileName
    if (Test-Path -LiteralPath $localManifestPath) {
        return @(Get-Content -LiteralPath $localManifestPath | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
    }

    if ([string]::IsNullOrWhiteSpace($PackageBaseUrl)) {
        return @()
    }

    try {
        $manifestUrl = Join-PackageUrl $PackageBaseUrl $manifestFileName
        Write-Host "Downloading $manifestFileName..."
        return @((Invoke-RestMethod -Uri $manifestUrl -UseBasicParsing) -split "`r?`n" | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
    }
    catch {
        throw "Could not download $manifestFileName from $PackageBaseUrl. Ping requires Microsoft Windows App Runtime dependency packages. $($_.Exception.Message)"
    }
}

function Resolve-DependencyPackagePaths([string]$TargetArchitecture) {
    $manifestLines = Resolve-DependencyManifestLines $TargetArchitecture
    $dependencyPaths = [System.Collections.Generic.List[string]]::new()
    $packageRoot = [System.IO.Path]::GetFullPath($PackageDirectory).TrimEnd([System.IO.Path]::DirectorySeparatorChar, [System.IO.Path]::AltDirectorySeparatorChar)

    foreach ($line in $manifestLines) {
        $trimmedLine = $line.Trim()
        $relativePath = $trimmedLine.Replace('/', [System.IO.Path]::DirectorySeparatorChar)
        if ($relativePath -match '^[a-zA-Z]+:|^\\|^[a-zA-Z][a-zA-Z0-9+.-]*:') {
            throw "Dependency manifest contains an absolute path or URI, which is not allowed: $line"
        }

        if ([System.IO.Path]::GetExtension($relativePath) -notin @(".msix", ".appx")) {
            throw "Dependency manifest entry must be an .msix or .appx package: $line"
        }

        $dependencyPath = Join-Path $PackageDirectory $relativePath
        $resolvedDependencyPath = [System.IO.Path]::GetFullPath($dependencyPath)
        if (-not $resolvedDependencyPath.StartsWith($packageRoot + [System.IO.Path]::DirectorySeparatorChar, [System.StringComparison]::OrdinalIgnoreCase)) {
            throw "Dependency manifest entry escapes the package directory: $line"
        }

        if (-not (Test-Path -LiteralPath $resolvedDependencyPath)) {
            if ([string]::IsNullOrWhiteSpace($PackageBaseUrl)) {
                throw "Missing framework dependency: $resolvedDependencyPath"
            }

            New-Item -ItemType Directory -Force -Path (Split-Path -Parent $resolvedDependencyPath) | Out-Null
            $dependencyUrl = Join-PackageUrl $PackageBaseUrl $trimmedLine
            Write-Host "Downloading $(Split-Path -Leaf $resolvedDependencyPath)..."
            Invoke-WebRequest -Uri $dependencyUrl -OutFile $resolvedDependencyPath -UseBasicParsing
        }

        $dependencyPaths.Add($resolvedDependencyPath)
    }

    if ($dependencyPaths.Count -eq 0) {
        Write-Warning "No framework dependency manifest was found for $TargetArchitecture. Continuing without -DependencyPath; this can fail with 0x80073CF3 on clean Windows installs."
    }

    return $dependencyPaths.ToArray()
}

function Test-SignatureMatchesCertificate($Signature, [string]$ExpectedCertificatePath) {
    if (-not $Signature.SignerCertificate) {
        return $false
    }

    $expectedCertificate = [Security.Cryptography.X509Certificates.X509Certificate2]::new($ExpectedCertificatePath)
    return $Signature.SignerCertificate.Thumbprint -eq $expectedCertificate.Thumbprint
}

try {
    if (-not (Test-Administrator)) {
        Write-Host "Ping needs one administrator prompt to trust the sideload certificate."
        Restart-Elevated
        return
    }

    Assert-SupportedWindowsVersion

    if ([string]::IsNullOrWhiteSpace($PackageBaseUrl) -and -not (Test-Path -LiteralPath $PackageDirectory)) {
        throw "Package directory does not exist: $PackageDirectory"
    }

    if (-not (Test-Path -LiteralPath $CertificatePath)) {
        throw "Missing sideload certificate: $CertificatePath"
    }

    $targetArchitecture = Resolve-Architecture
    $Version = Resolve-Version $targetArchitecture
    $packageFileName = switch ($targetArchitecture) {
        "x64" { "Ping-Windows-v$Version-x64.msix" }
        "arm64" { "Ping-Windows-v$Version-arm64.msix" }
    }
    $packagePath = Join-Path $PackageDirectory $packageFileName

    Download-PackageIfNeeded $packagePath $packageFileName
    $dependencyPaths = Resolve-DependencyPackagePaths $targetArchitecture

    Write-Host "Trusting Ping sideload certificate..."
    Import-Certificate -CertStoreLocation "Cert:\LocalMachine\TrustedPeople" -FilePath $CertificatePath | Out-Null

    $signature = Get-AuthenticodeSignature -LiteralPath $packagePath
    if (-not (Test-SignatureMatchesCertificate $signature $CertificatePath)) {
        if ($AllowUnsigned) {
            Write-Warning "The MSIX signer does not match Ping-Windows-Sideload.cer. Proceeding because -AllowUnsigned was provided."
        } else {
            throw "The MSIX signer does not match Ping-Windows-Sideload.cer. Refusing to install an unexpected package."
        }
    }
    elseif ($signature.Status -ne "Valid") {
        Write-Warning "The MSIX signer matches Ping-Windows-Sideload.cer, but signature status is $($signature.Status). Continuing after trusting the bundled certificate."
    }

    Write-Host "Installing $packageFileName..."
    if ($dependencyPaths.Count -gt 0) {
        Add-AppxPackage -Path $packagePath -DependencyPath $dependencyPaths -ForceUpdateFromAnyVersion
    } else {
        Add-AppxPackage -Path $packagePath -ForceUpdateFromAnyVersion
    }

    $installed = Get-AppxPackage -Name $packageName |
        Sort-Object InstallDate -Descending |
        Select-Object -First 1
    if (-not $installed) {
        throw "Ping package did not appear in Get-AppxPackage after installation."
    }

    # Icon 복사 및 단축키 구성
    $appDataPing = Join-Path $env:LOCALAPPDATA "Ping"
    if (-not (Test-Path -LiteralPath $appDataPing)) {
        New-Item -ItemType Directory -Force -Path $appDataPing | Out-Null
    }

    $localIconPath = ""
    if (-not [string]::IsNullOrWhiteSpace($IconPath) -and (Test-Path -LiteralPath $IconPath)) {
        $localIconPath = Join-Path $appDataPing "app.ico"
        Copy-Item -LiteralPath $IconPath -Destination $localIconPath -Force
    }

    $wshShell = New-Object -ComObject WScript.Shell

    if ($CreateDesktopShortcut) {
        Write-Host "Creating desktop shortcut..."
        $desktopPath = [System.IO.Path]::Combine([System.Environment]::GetFolderPath("Desktop"), "Ping.lnk")
        $shortcut = $wshShell.CreateShortcut($desktopPath)
        $shortcut.TargetPath = "explorer.exe"
        $shortcut.Arguments = "shell:AppsFolder\$($installed.PackageFamilyName)!App"
        if (-not [string]::IsNullOrWhiteSpace($localIconPath)) {
            $shortcut.IconLocation = $localIconPath
        }
        $shortcut.Save()
    }

    if ($CreateStartMenuShortcut) {
        Write-Host "Creating Start menu shortcut..."
        $programsPath = [System.Environment]::GetFolderPath("Programs")
        $pingStartMenuFolder = [System.IO.Path]::Combine($programsPath, "Ping")
        New-Item -ItemType Directory -Force -Path $pingStartMenuFolder | Out-Null
        $shortcut = $wshShell.CreateShortcut([System.IO.Path]::Combine($pingStartMenuFolder, "Ping.lnk"))
        $shortcut.TargetPath = "explorer.exe"
        $shortcut.Arguments = "shell:AppsFolder\$($installed.PackageFamilyName)!App"
        if (-not [string]::IsNullOrWhiteSpace($localIconPath)) {
            $shortcut.IconLocation = $localIconPath
        }
        $shortcut.Save()
    }

    if ($AddToStartup) {
        Write-Host "Adding to startup folder..."
        $startupFolder = [System.Environment]::GetFolderPath("Startup")
        $startupPath = [System.IO.Path]::Combine($startupFolder, "Ping.lnk")
        $shortcut = $wshShell.CreateShortcut($startupPath)
        $shortcut.TargetPath = "explorer.exe"
        $shortcut.Arguments = "shell:AppsFolder\$($installed.PackageFamilyName)!App"
        if (-not [string]::IsNullOrWhiteSpace($localIconPath)) {
            $shortcut.IconLocation = $localIconPath
        }
        $shortcut.Save()
    }

    if (-not $NoLaunch) {
        Start-Process "shell:AppsFolder\$($installed.PackageFamilyName)!App"
    }

    Write-Host "Ping for Windows is installed."
}
catch {
    try {
        Add-Type -AssemblyName PresentationFramework -ErrorAction SilentlyContinue
        [System.Windows.MessageBox]::Show("Ping 설치 중 오류가 발생했습니다:`n`n$($_.Exception.Message)", "Ping 설치 오류", "OK", "Error") | Out-Null
    }
    catch {
        Write-Error "Ping 설치 오류: $($_.Exception.Message)"
    }
    throw $_
}
