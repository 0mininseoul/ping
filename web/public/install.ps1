# Ping for Windows Remote Installer
$ErrorActionPreference = "Stop"

function Test-Administrator {
    $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = [Security.Principal.WindowsPrincipal]::new($identity)
    return $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
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
        Write-Warning "Windows 빌드 정보를 레지스트리에서 읽지 못해 Environment.OSVersion으로 대체합니다. $($_.Exception.Message)"
    }

    return [Environment]::OSVersion.Version.Build
}

function Assert-SupportedWindowsVersion {
    $minimumBuild = 26100
    $build = Get-CurrentWindowsBuild
    if ($build -lt $minimumBuild) {
        throw "Ping for Windows는 Windows 11 24H2 이상(build $minimumBuild+)에서만 설치할 수 있습니다. 현재 PC build: $build. Windows Update 후 다시 설치해 주세요."
    }
}

function Test-SignatureMatchesCertificate($Signature, [string]$ExpectedCertificatePath) {
    if (-not $Signature.SignerCertificate) {
        return $false
    }

    $expectedCertificate = [Security.Cryptography.X509Certificates.X509Certificate2]::new($ExpectedCertificatePath)
    return $Signature.SignerCertificate.Thumbprint -eq $expectedCertificate.Thumbprint
}

if (-not (Test-Administrator)) {
    Write-Host "Ping 설치를 진행하기 위해 관리자 권한이 필요합니다..."
    Start-Process powershell.exe -Verb RunAs -ArgumentList "-NoProfile -ExecutionPolicy Bypass -Command `"& { [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12; irm https://0minping.vercel.app/install.ps1 | iex }`""
    return
}

Assert-SupportedWindowsVersion

$packageName = "YoungminPark.PingWindows"
$baseUrl = "https://0minping.vercel.app/downloads/windows"
$tempDir = Join-Path $env:TEMP "PingSetup"

Remove-Item -Recurse -Force -LiteralPath $tempDir -ErrorAction SilentlyContinue
New-Item -ItemType Directory -Force -Path $tempDir | Out-Null

Write-Host "1. 최신 버전 정보 확인 중..."
$versionUrl = "$baseUrl/latest-version.txt"
$version = (Invoke-RestMethod -Uri $versionUrl -UseBasicParsing).Trim()
Write-Host "최신 버전: v$version"

# 아키텍처 판별
$arch = "x64"
if ([System.Runtime.InteropServices.RuntimeInformation]::ProcessArchitecture -eq [System.Runtime.InteropServices.Architecture]::Arm64) {
    $arch = "arm64"
}
Write-Host "시스템 아키텍처: $arch"

Write-Host "2. 보안 인증서 및 설치 파일 다운로드 중..."
$certPath = Join-Path $tempDir "Ping-Windows-Sideload.cer"
$msixFileName = "Ping-Windows-v$version-$arch.msix"
$msixPath = Join-Path $tempDir $msixFileName
$icoPath = Join-Path $tempDir "app.ico"

Invoke-WebRequest -Uri "$baseUrl/Ping-Windows-Sideload.cer" -OutFile $certPath -UseBasicParsing
Invoke-WebRequest -Uri "$baseUrl/$msixFileName" -OutFile $msixPath -UseBasicParsing

$dependencyPaths = @()
$dependencyManifestUrl = "$baseUrl/dependencies-$arch.txt"
$packageRoot = [System.IO.Path]::GetFullPath($tempDir).TrimEnd([System.IO.Path]::DirectorySeparatorChar, [System.IO.Path]::AltDirectorySeparatorChar)
try {
    $dependencyManifest = (Invoke-RestMethod -Uri $dependencyManifestUrl -UseBasicParsing) -split "`r?`n" |
        Where-Object { -not [string]::IsNullOrWhiteSpace($_) }
    foreach ($dependencyRelativePath in $dependencyManifest) {
        $trimmedDependencyPath = $dependencyRelativePath.Trim()
        $safeRelativePath = $trimmedDependencyPath.Replace('/', [System.IO.Path]::DirectorySeparatorChar)
        if ($safeRelativePath -match '^[a-zA-Z]+:|^\\|^[a-zA-Z][a-zA-Z0-9+.-]*:') {
            throw "Dependency manifest contains an absolute path or URI: $dependencyRelativePath"
        }
        if ([System.IO.Path]::GetExtension($safeRelativePath) -notin @(".msix", ".appx")) {
            throw "Dependency manifest entry must be an .msix or .appx package: $dependencyRelativePath"
        }

        $dependencyPath = Join-Path $tempDir $safeRelativePath
        $resolvedDependencyPath = [System.IO.Path]::GetFullPath($dependencyPath)
        if (-not $resolvedDependencyPath.StartsWith($packageRoot + [System.IO.Path]::DirectorySeparatorChar, [System.StringComparison]::OrdinalIgnoreCase)) {
            throw "Dependency manifest entry escapes the installer temp directory: $dependencyRelativePath"
        }

        New-Item -ItemType Directory -Force -Path (Split-Path -Parent $resolvedDependencyPath) | Out-Null
        Write-Host "프레임워크 의존성 다운로드 중: $(Split-Path -Leaf $resolvedDependencyPath)"
        Invoke-WebRequest -Uri "$baseUrl/$trimmedDependencyPath" -OutFile $resolvedDependencyPath -UseBasicParsing
        $dependencyPaths += $resolvedDependencyPath
    }
}
catch {
    throw "Windows App Runtime 의존성 목록을 다운로드하지 못했습니다. 깨끗한 Windows 11 PC에서는 이 파일이 없으면 0x80073CF3 오류가 발생합니다. $($_.Exception.Message)"
}

# 아이콘 다운로드 (Inno Setup 빌드 시 생성된 app.ico가 Vercel /downloads/windows/app.ico 경로에 올라가도록 처리)
Invoke-WebRequest -Uri "$baseUrl/app.ico" -OutFile $icoPath -UseBasicParsing -ErrorAction SilentlyContinue

Write-Host "3. Ping 개발자 보안 인증서 등록 중..."
Import-Certificate -CertStoreLocation "Cert:\LocalMachine\TrustedPeople" -FilePath $certPath | Out-Null

$signature = Get-AuthenticodeSignature -LiteralPath $msixPath
if (-not (Test-SignatureMatchesCertificate $signature $certPath)) {
    throw "다운로드한 Ping MSIX 서명자가 Ping-Windows-Sideload.cer와 일치하지 않습니다. 설치를 중단합니다."
}
if ($signature.Status -ne "Valid") {
    Write-Warning "MSIX 서명자는 Ping-Windows-Sideload.cer와 일치하지만 서명 상태가 $($signature.Status)입니다. 인증서를 신뢰 저장소에 등록했으므로 설치를 계속합니다."
}

Write-Host "4. MSIX 앱 패키지 설치 중..."
if ($dependencyPaths.Count -gt 0) {
    Add-AppxPackage -Path $msixPath -DependencyPath $dependencyPaths -ForceUpdateFromAnyVersion
} else {
    Add-AppxPackage -Path $msixPath -ForceUpdateFromAnyVersion
}

# 설치된 패키지 확인
$installed = Get-AppxPackage -Name $packageName |
    Sort-Object InstallDate -Descending |
    Select-Object -First 1

if (-not $installed) {
    throw "Ping 패키지 설치 실패 (Get-AppxPackage에서 찾을 수 없음)"
}

Write-Host "5. 바로가기 및 시작 프로그램 구성 중..."
# 로컬 앱데이터 폴더에 아이콘 복사
$appDataPing = Join-Path $env:LOCALAPPDATA "Ping"
if (-not (Test-Path -LiteralPath $appDataPing)) {
    New-Item -ItemType Directory -Force -Path $appDataPing | Out-Null
}
$localIconPath = ""
if (Test-Path -LiteralPath $icoPath) {
    $localIconPath = Join-Path $appDataPing "app.ico"
    Copy-Item -LiteralPath $icoPath -Destination $localIconPath -Force
}

$wshShell = New-Object -ComObject WScript.Shell

# 바탕화면 바로가기
$desktopPath = [System.IO.Path]::Combine([System.Environment]::GetFolderPath("Desktop"), "Ping.lnk")
$shortcut = $wshShell.CreateShortcut($desktopPath)
$shortcut.TargetPath = "explorer.exe"
$shortcut.Arguments = "shell:AppsFolder\$($installed.PackageFamilyName)!App"
if (-not [string]::IsNullOrWhiteSpace($localIconPath)) {
    $shortcut.IconLocation = $localIconPath
}
$shortcut.Save()

# 시작프로그램 등록
$startupFolder = [System.Environment]::GetFolderPath("Startup")
$startupPath = [System.IO.Path]::Combine($startupFolder, "Ping.lnk")
$shortcut = $wshShell.CreateShortcut($startupPath)
$shortcut.TargetPath = "explorer.exe"
$shortcut.Arguments = "shell:AppsFolder\$($installed.PackageFamilyName)!App"
if (-not [string]::IsNullOrWhiteSpace($localIconPath)) {
    $shortcut.IconLocation = $localIconPath
}
$shortcut.Save()

# 임시 파일 정리
Remove-Item -Recurse -Force -LiteralPath $tempDir -ErrorAction SilentlyContinue

Write-Host "6. 설치 완료! Ping을 실행합니다..."
Start-Process "shell:AppsFolder\$($installed.PackageFamilyName)!App"
Write-Host "설치가 정상적으로 성공했습니다."
