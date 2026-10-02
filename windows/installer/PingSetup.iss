#define AppVersion GetEnv("PING_VERSION")
#define PayloadRoot GetEnv("PING_INSTALLER_PAYLOAD_ROOT")
#define OutputRoot GetEnv("PING_INSTALLER_OUTPUT_DIR")

[Setup]
AppId={{4DD8F1D2-8C4E-4D0D-9A48-FE2B4A906F01}
AppName=Ping
AppVersion={#AppVersion}
AppPublisher=Youngmin Park
AppPublisherURL=https://0minping.vercel.app
AppSupportURL=https://github.com/0mininseoul/ping/releases
DefaultDirName={localappdata}\Programs\Ping
DefaultGroupName=Ping
OutputDir={#OutputRoot}
OutputBaseFilename=PingSetup-v{#AppVersion}
Compression=lzma2
SolidCompression=yes
WizardStyle=modern
PrivilegesRequired=lowest
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
Name: "launch"; Description: "설치 완료 후 즉시 Ping 실행"; GroupDescription: "추가 옵션:"; Flags: checkedonce

[Files]
Source: "{#PayloadRoot}\Ping-Windows-Sideload.cer"; DestDir: "{tmp}"; Flags: deleteafterinstall
Source: "{#PayloadRoot}\Ping-Windows-Sideload.cer"; DestDir: "{app}"; Flags: ignoreversion
Source: "{#PayloadRoot}\install-ping-windows.ps1"; DestDir: "{tmp}"; Flags: deleteafterinstall
Source: "{#PayloadRoot}\uninstall-ping-windows.ps1"; DestDir: "{app}"; Flags: ignoreversion
Source: "{#PayloadRoot}\ping-user-data.ps1"; DestDir: "{tmp}"; Flags: deleteafterinstall
Source: "{#PayloadRoot}\ping-user-data.ps1"; DestDir: "{app}"; Flags: ignoreversion
Source: "{#PayloadRoot}\Ping-Windows-v{#AppVersion}-x64.msix"; DestDir: "{tmp}"; Flags: deleteafterinstall; Check: not IsArm64
Source: "{#PayloadRoot}\Ping-Windows-v{#AppVersion}-arm64.msix"; DestDir: "{tmp}"; Flags: deleteafterinstall; Check: IsArm64
Source: "{#PayloadRoot}\dependencies-x64.txt"; DestDir: "{tmp}"; Flags: deleteafterinstall; Check: not IsArm64
Source: "{#PayloadRoot}\dependencies-arm64.txt"; DestDir: "{tmp}"; Flags: deleteafterinstall; Check: IsArm64
Source: "{#PayloadRoot}\Dependencies\x64\*"; DestDir: "{tmp}\Dependencies\x64"; Flags: deleteafterinstall recursesubdirs; Check: not IsArm64
Source: "{#PayloadRoot}\Dependencies\arm64\*"; DestDir: "{tmp}\Dependencies\arm64"; Flags: deleteafterinstall recursesubdirs; Check: IsArm64
Source: "app.ico"; DestDir: "{tmp}"; Flags: deleteafterinstall
Source: "app.ico"; DestDir: "{app}"; Flags: ignoreversion

[UninstallDelete]
Type: files; Name: "{app}\package-family.txt"

[Code]
var
  RegistrationProgress: TOutputMarqueeProgressWizardPage;

function IsArm64: Boolean;
begin
  Result := ProcessorArchitecture = paArm64;
end;

procedure InitializeWizard;
begin
  RegistrationProgress := CreateOutputMarqueeProgressPage('Ping 설치', 'Windows에 앱을 등록하고 있습니다.');
end;
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

{ 앱과 의존성은 EXE에서 현재 사용자 임시 폴더로 압축 해제한다. }
function GetInstallerParams: String;
var
  Params: String;
begin
  Params :=
    '-Version "{#AppVersion}"' +
    ' -Architecture ' + MsixArchitecture +
    ' -PackageDirectory "' + ExpandConstant('{tmp}') + '"' +
    ' -NoDialogs' +
    ' -RegistrationRecordPath "' + ExpandConstant('{app}\package-family.txt') + '"' +
    ' -CertificatePath "' + ExpandConstant('{tmp}\Ping-Windows-Sideload.cer') + '"' +
    ' -IconPath "' + ExpandConstant('{tmp}\app.ico') + '"';

  if WizardIsTaskSelected('desktopicon') then
    Params := Params + ' -CreateDesktopShortcut';

  if WizardIsTaskSelected('startmenu') then
    Params := Params + ' -CreateStartMenuShortcut';

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

    RegistrationProgress.SetText('앱 등록 중…', '필요하면 인증서 신뢰 단계에서만 관리자 권한을 요청합니다. 자동 시작은 Ping 설정에서 선택할 수 있습니다.');
    RegistrationProgress.Show;
    RegistrationProgress.Animate;
    try
      repeat
        if not Exec(ExpandConstant('{sys}\WindowsPowerShell\v1.0\powershell.exe'),
          CommandLine, '', SW_HIDE, ewWaitUntilTerminated, ResultCode) then
          ResultCode := -1;
        if ResultCode = 0 then Break;
        if SuppressibleMsgBox('Ping을 설치하지 못했습니다. 트레이에서 Ping을 종료하고 인증서 승인과 Windows 버전을 확인해 주세요.' + #13#10 +
          '기존 계정과 설정은 유지됩니다. 다시 시도할까요?', mbError, MB_RETRYCANCEL, IDCANCEL) = IDCANCEL then Abort;
      until False;
    finally
      RegistrationProgress.Hide;
    end;
  end;
end;

procedure CurUninstallStepChanged(CurUninstallStep: TUninstallStep);
var
  CommandLine: String;
  ResultCode: Integer;
begin
  if CurUninstallStep <> usUninstall then Exit;
  CommandLine := '-NoProfile -ExecutionPolicy Bypass -File "' + ExpandConstant('{app}\uninstall-ping-windows.ps1') + '" -NoDialogs';
  if not Exec(ExpandConstant('{sys}\WindowsPowerShell\v1.0\powershell.exe'),
    CommandLine, '', SW_HIDE, ewWaitUntilTerminated, ResultCode) then ResultCode := -1;
  if ResultCode <> 0 then
  begin
    SuppressibleMsgBox('Ping을 제거하지 못했습니다. 트레이에서 Ping을 종료한 뒤 다시 시도해 주세요. 계정 보존 파일과 설치 관리자는 유지됩니다.', mbError, MB_OK, IDOK);
    Abort;
  end;
end;
