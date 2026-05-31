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
InfoBeforeFile=welcome.txt
SetupIconFile=app.ico

[Tasks]
Name: "desktopicon"; Description: "바탕 화면에 바로가기 만들기"; GroupDescription: "추가 옵션:"
Name: "startup"; Description: "Windows 부팅 시 자동 시작 등록"; GroupDescription: "추가 옵션:"
Name: "launch"; Description: "설치 완료 후 즉시 Ping 실행"; GroupDescription: "추가 옵션:"

[Files]
Source: "{#PayloadRoot}\Ping-Windows-Sideload.cer"; DestDir: "{tmp}"; Flags: deleteafterinstall
Source: "{#PayloadRoot}\install-ping-windows.ps1"; DestDir: "{tmp}"; Flags: deleteafterinstall
Source: "app.ico"; DestDir: "{tmp}"; Flags: deleteafterinstall

[Code]
var
  DownloadPage: TDownloadWizardPage;

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

function MsixDownloadUrl: String;
begin
  Result := '{#PackageBaseUrl}/' + MsixFileName;
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
    ' -IconPath "' + ExpandConstant('{tmp}\app.ico') + '"' +
    ' -AllowUnsigned';

  if WizardIsTaskSelected('desktopicon') then
    Params := Params + ' -CreateDesktopShortcut';

  if WizardIsTaskSelected('startup') then
    Params := Params + ' -AddToStartup';

  if not WizardIsTaskSelected('launch') then
    Params := Params + ' -NoLaunch';

  Result := Params;
end;

procedure InitializeWizard;
begin
  DownloadPage := CreateDownloadPage(
    'Ping 설치 파일 다운로드',
    'Ping 앱 패키지를 내려받는 중입니다. 잠시만 기다려 주세요.',
    nil);
end;

{ 사용자가 '설치'를 누르면 진행률 페이지에서 MSIX를 내려받는다.
  실패하면 한국어 안내 후 준비 페이지에 머물러 재시도할 수 있게 한다. }
function NextButtonClick(CurPageID: Integer): Boolean;
begin
  if CurPageID = wpReady then
  begin
    DownloadPage.Clear;
    DownloadPage.Add(MsixDownloadUrl, MsixFileName, '');
    DownloadPage.Show;
    try
      try
        DownloadPage.Download;
        Result := True;
      except
        if DownloadPage.AbortedByUser then
          Log('사용자가 다운로드를 취소했습니다.')
        else
          SuppressibleMsgBox(
            '설치 파일을 내려받지 못했습니다.' + #13#10 + #13#10 +
            '인터넷 연결을 확인한 뒤 다시 시도해 주세요.' + #13#10 +
            '(' + GetExceptionMessage + ')',
            mbCriticalError, MB_OK, IDOK);
        Result := False;
      end;
    finally
      DownloadPage.Hide;
    end;
  end
  else
    Result := True;
end;

{ 다운로드가 끝난 뒤 인증서 등록 + MSIX 설치를 숨김 모드로 실행하고,
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
