# Ping for Windows Remote Installer
$ErrorActionPreference = "Stop"

function Test-Administrator {
    $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = [Security.Principal.WindowsPrincipal]::new($identity)
    return $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

if (-not (Test-Administrator)) {
    Write-Host "Ping 설치를 진행하기 위해 관리자 권한이 필요합니다..."
    Start-Process powershell.exe -Verb RunAs -ArgumentList "-NoProfile -ExecutionPolicy Bypass -Command `"& { [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12; irm https://0minping.vercel.app/install.ps1 | iex }`""
    return
}

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

# 아이콘 다운로드 (Inno Setup 빌드 시 생성된 app.ico가 Vercel /downloads/windows/app.ico 경로에 올라가도록 처리)
Invoke-WebRequest -Uri "$baseUrl/app.ico" -OutFile $icoPath -UseBasicParsing -ErrorAction SilentlyContinue

Write-Host "3. Ping 개발자 보안 인증서 등록 중..."
Import-Certificate -CertStoreLocation "Cert:\LocalMachine\TrustedPeople" -FilePath $certPath | Out-Null

Write-Host "4. MSIX 앱 패키지 설치 중..."
Add-AppxPackage -Path $msixPath -ForceUpdateFromAnyVersion

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
