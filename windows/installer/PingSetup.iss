#define AppVersion GetEnv("PING_VERSION")
#define PayloadRoot GetEnv("PING_INSTALLER_PAYLOAD_ROOT")
#define OutputRoot GetEnv("PING_INSTALLER_OUTPUT_DIR")
#define PackageBaseUrl GetEnv("PING_INSTALLER_PACKAGE_BASE_URL")

[Setup]
AppId={{4DD8F1D2-8C4E-4D0D-9A48-FE2B4A906F01}
AppName=Ping
AppVersion={#AppVersion}
AppPublisher=Youngmin Park
AppPublisherURL=https://0minping.vercel.app
AppSupportURL=https://github.com/0mininseoul/ping/releases
DefaultDirName={autopf}\Ping
DefaultGroupName=Ping
OutputDir={#OutputRoot}
OutputBaseFilename=PingSetup-v{#AppVersion}
Compression=lzma2
SolidCompression=yes
WizardStyle=modern
PrivilegesRequired=admin
ArchitecturesAllowed=x64compatible arm64
ArchitecturesInstallIn64BitMode=x64compatible arm64
DisableDirPage=no
AlwaysShowDirOnReadyPage=yes
MinVersion=10.0.26100
SetupLogging=yes
InfoBeforeFile=welcome.txt
SetupIconFile=app.ico

[Tasks]
Name: "desktopicon"; Description: "바탕 화면에 바로가기 만들기"; GroupDescription: "추가 옵션:"
Name: "startmenu"; Description: "시작 메뉴에 Ping 폴더 및 바로가기 만들기"; GroupDescription: "추가 옵션:"; Flags: checkedonce
Name: "startup"; Description: "Windows 부팅 시 자동 시작 등록"; GroupDescription: "추가 옵션:"
Name: "launch"; Description: "설치 완료 후 즉시 Ping 실행"; GroupDescription: "추가 옵션:"; Flags: checkedonce

[Files]
Source: "{#PayloadRoot}\Ping-Windows-v*-x64.msix"; DestDir: "{tmp}"; Flags: deleteafterinstall
Source: "{#PayloadRoot}\Ping-Windows-v*-arm64.msix"; DestDir: "{tmp}"; Flags: deleteafterinstall
Source: "{#PayloadRoot}\Ping-Windows-Sideload.cer"; DestDir: "{tmp}"; Flags: deleteafterinstall
Source: "{#PayloadRoot}\Ping-Windows-Sideload.cer"; DestDir: "{app}"; Flags: ignoreversion
Source: "{#PayloadRoot}\install-ping-windows.ps1"; DestDir: "{tmp}"; Flags: deleteafterinstall
Source: "{#PayloadRoot}\uninstall-ping-windows.ps1"; DestDir: "{app}"; Flags: ignoreversion
Source: "{#PayloadRoot}\dependencies-*.txt"; DestDir: "{tmp}"; Flags: deleteafterinstall
Source: "{#PayloadRoot}\Dependencies\*"; DestDir: "{tmp}\Dependencies"; Flags: recursesubdirs createallsubdirs deleteafterinstall
Source: "app.ico"; DestDir: "{tmp}"; Flags: deleteafterinstall
Source: "app.ico"; DestDir: "{app}"; Flags: ignoreversion

[UninstallRun]
Filename: "{sys}\WindowsPowerShell\v1.0\powershell.exe"; Parameters: "-NoProfile -ExecutionPolicy Bypass -File ""{app}\uninstall-ping-windows.ps1"" -CertificatePath ""{app}\Ping-Windows-Sideload.cer"""; Flags: runhidden waituntilterminated

[Code]
{ x64 또는 arm64 중 현재 PC에 맞는 패키지를 고른다. }
function MsixArchitecture: String;
begin
  if ProcessorArchitecture = paArm64 then
    Result := 'arm64'
  else
    Result := 'x64';
end;

function MsixFileName: String;
begin
  Result := 'Ping-Windows-v{#AppVersion}-' + MsixArchitecture + '.msix';
end;

{ install-ping-windows.ps1에 전달할 인자. 이미 내려받은 로컬 MSIX만 사용하도록
  PackageBaseUrl은 넘기지 않는다(설치 중 추가 다운로드 없음). }
function GetInstallerParams: String;
var
  Params: String;
begin
  Params :=
    '-Version "{#AppVersion}"' +
    ' -Architecture ' + MsixArchitecture +
    ' -PackageDirectory "' + ExpandConstant('{tmp}') + '"' +
    ' -CertificatePath "' + ExpandConstant('{tmp}\Ping-Windows-Sideload.cer') + '"' +
    ' -IconPath "' + ExpandConstant('{tmp}\app.ico') + '"';

  if WizardIsTaskSelected('desktopicon') then
    Params := Params + ' -CreateDesktopShortcut';

  if WizardIsTaskSelected('startmenu') then
    Params := Params + ' -CreateStartMenuShortcut';

  if WizardIsTaskSelected('startup') then
    Params := Params + ' -AddToStartup';

  if not WizardIsTaskSelected('launch') then
    Params := Params + ' -NoLaunch';

  Result := Params;
end;

{ 파일 압축 해제 뒤 인증서 등록 + MSIX 설치를 숨김 모드로 실행하고,
  종료 코드를 확인해 실패 시 설치를 정확히 중단한다(거짓 '완료' 방지). }
procedure CurStepChanged(CurStep: TSetupStep);
var
  ScriptPath: String;
  CommandLine: String;
  ResultCode: Integer;
begin
  if CurStep = ssPostInstall then
  begin
    ScriptPath := ExpandConstant('{tmp}\install-ping-windows.ps1');
    CommandLine :=
      '-NoProfile -ExecutionPolicy Bypass -File "' + ScriptPath + '" ' + GetInstallerParams;

    if not Exec(
      ExpandConstant('{sys}\WindowsPowerShell\v1.0\powershell.exe'),
      CommandLine, '', SW_HIDE, ewWaitUntilTerminated, ResultCode) then
    begin
      MsgBox(
        'Ping 설치 프로그램을 실행하지 못했습니다.' + #13#10 +
        'Windows PowerShell을 찾을 수 없습니다.',
        mbCriticalError, MB_OK);
      Abort;
    end;

    if ResultCode <> 0 then
      { install-ping-windows.ps1이 이미 한국어 오류 창을 표시했으므로 중단만 한다. }
      Abort;
  end;
end;
