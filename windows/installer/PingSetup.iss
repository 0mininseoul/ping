#define AppVersion GetEnv("PING_VERSION")
#define PayloadRoot GetEnv("PING_INSTALLER_PAYLOAD_ROOT")
#define OutputRoot GetEnv("PING_INSTALLER_OUTPUT_DIR")
#define PackageBaseUrl GetEnv("PING_INSTALLER_PACKAGE_BASE_URL")

[Setup]
AppId={{4DD8F1D2-8C4E-4D0D-9A48-FE2B4A906F01}
AppName=Ping
AppVersion={#AppVersion}
AppPublisher=Youngmin Park
AppPublisherURL=https://ping0min.vercel.app
AppSupportURL=https://github.com/0mininseoul/ping/releases
DefaultDirName={autopf}\Ping
DisableDirPage=yes
DisableProgramGroupPage=yes
OutputDir={#OutputRoot}
OutputBaseFilename=PingSetup-v{#AppVersion}
Compression=lzma2
SolidCompression=yes
WizardStyle=modern
PrivilegesRequired=admin
ArchitecturesAllowed=x64compatible arm64
ArchitecturesInstallIn64BitMode=x64compatible arm64
Uninstallable=no
SetupLogging=yes
InfoBeforeFile=welcome.rtf
SetupIconFile=app.ico

[Tasks]
Name: "desktopicon"; Description: "바탕 화면에 바로가기 만들기"; GroupDescription: "추가 옵션:"
Name: "startup"; Description: "Windows 부팅 시 자동 시작 등록"; GroupDescription: "추가 옵션:"
Name: "launch"; Description: "설치 완료 후 즉시 Ping 실행"; GroupDescription: "추가 옵션:"

[Files]
Source: "{#PayloadRoot}\Ping-Windows-Sideload.cer"; DestDir: "{tmp}\PingSetup"; Flags: deleteafterinstall
Source: "{#PayloadRoot}\install-ping-windows.ps1"; DestDir: "{tmp}\PingSetup"; Flags: deleteafterinstall
Source: "app.ico"; DestDir: "{tmp}\PingSetup"; Flags: deleteafterinstall

[Run]
Filename: "{sys}\WindowsPowerShell\v1.0\powershell.exe"; Parameters: "-NoProfile -ExecutionPolicy Bypass -File ""{tmp}\PingSetup\install-ping-windows.ps1"" {code:GetInstallerParams}"; StatusMsg: "Installing Ping for Windows..."; Flags: runhidden waituntilterminated

[Code]
function GetInstallerParams(Param: String): String;
var
  Params: String;
begin
  Params := '-Version "' + ExpandConstant('{#AppVersion}') + '" -PackageDirectory "' + ExpandConstant('{tmp}\PingSetup') + '" -PackageBaseUrl "' + ExpandConstant('{#PackageBaseUrl}') + '" -CertificatePath "' + ExpandConstant('{tmp}\PingSetup\Ping-Windows-Sideload.cer') + '" -IconPath "' + ExpandConstant('{tmp}\PingSetup\app.ico') + '"';
  
  if WizardIsTaskSelected('desktopicon') then
    Params := Params + ' -CreateDesktopShortcut';
    
  if WizardIsTaskSelected('startup') then
    Params := Params + ' -AddToStartup';
    
  if not WizardIsTaskSelected('launch') then
    Params := Params + ' -NoLaunch';
    
  Result := Params;
end;
