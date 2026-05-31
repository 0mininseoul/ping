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

try {
    if (-not (Test-Administrator)) {
        Write-Host "Ping needs one administrator prompt to trust the sideload certificate."
        Restart-Elevated
        return
    }

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

    Write-Host "Trusting Ping sideload certificate..."
    Import-Certificate -CertStoreLocation "Cert:\LocalMachine\TrustedPeople" -FilePath $CertificatePath | Out-Null

    $signature = Get-AuthenticodeSignature -LiteralPath $packagePath
    if ($signature.Status -ne "Valid") {
        if ($AllowUnsigned) {
            Write-Warning "The MSIX signature is $($signature.Status), not Valid. Proceeding because -AllowUnsigned was provided."
        } else {
            throw "The MSIX signature is $($signature.Status), not Valid. Make sure this package was signed with Ping-Windows-Sideload.cer."
        }
    }

    Write-Host "Installing $packageFileName..."
    Add-AppxPackage -Path $packagePath -ForceUpdateFromAnyVersion

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
