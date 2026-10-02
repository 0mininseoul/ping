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
Source: "{#PayloadRoot}\Ping-Windows-Sideload.cer"; DestDir: "{tmp}"; Flags: dontcopy
Source: "{#PayloadRoot}\Ping-Windows-Sideload.cer"; DestDir: "{app}"; Flags: ignoreversion
Source: "{#PayloadRoot}\install-ping-windows.ps1"; DestDir: "{tmp}"; Flags: dontcopy
Source: "{#PayloadRoot}\uninstall-ping-windows.ps1"; DestDir: "{app}"; Flags: ignoreversion
Source: "{#PayloadRoot}\ping-user-data.ps1"; DestDir: "{tmp}"; Flags: dontcopy
Source: "{#PayloadRoot}\ping-user-data.ps1"; DestDir: "{app}"; Flags: ignoreversion
Source: "{#PayloadRoot}\Ping-Windows-v{#AppVersion}-x64.msix"; DestDir: "{tmp}"; Flags: dontcopy; Check: not IsArm64
Source: "{#PayloadRoot}\Ping-Windows-v{#AppVersion}-arm64.msix"; DestDir: "{tmp}"; Flags: dontcopy; Check: IsArm64
Source: "{#PayloadRoot}\dependencies-x64.txt"; DestDir: "{tmp}"; Flags: dontcopy; Check: not IsArm64
Source: "{#PayloadRoot}\dependencies-arm64.txt"; DestDir: "{tmp}"; Flags: dontcopy; Check: IsArm64
Source: "{#PayloadRoot}\Dependencies\x64\*"; DestDir: "{tmp}\Dependencies\x64"; Flags: dontcopy recursesubdirs; Check: not IsArm64
Source: "{#PayloadRoot}\Dependencies\arm64\*"; DestDir: "{tmp}\Dependencies\arm64"; Flags: dontcopy recursesubdirs; Check: IsArm64
Source: "app.ico"; DestDir: "{tmp}"; Flags: dontcopy
Source: "app.ico"; DestDir: "{app}"; Flags: ignoreversion

[Code]
var
  RegistrationProgress: TOutputMarqueeProgressWizardPage;

function SetProcessEnvironment(const Name, Value: String): Boolean;
  external 'SetEnvironmentVariableW@kernel32.dll stdcall';

function ExecWindowsPowerShell(const Params: String; var ResultCode: Integer): Boolean;
var
  PreviousModulePath: String;
begin
  PreviousModulePath := GetEnv('PSModulePath');
  if not SetProcessEnvironment('PSModulePath', ExpandConstant('{win}\System32\WindowsPowerShell\v1.0\Modules')) then
    RaiseException('Could not prepare Windows PowerShell module paths.');
  try
    Result := ExecAndLogOutput(ExpandConstant('{sys}\WindowsPowerShell\v1.0\powershell.exe'),
      Params, '', SW_HIDE, ewWaitUntilTerminated, ResultCode, nil);
  finally
    SetProcessEnvironment('PSModulePath', PreviousModulePath);
  end;
end;

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
    ' -NoDialogs -NoLaunch' +
    ' -RegistrationRecordPath "' + ExpandConstant('{tmp}\package-family.txt') + '"' +
    ' -CertificatePath "' + ExpandConstant('{tmp}\Ping-Windows-Sideload.cer') + '"' +
    ' -IconPath "' + ExpandConstant('{tmp}\app.ico') + '"';

  if WizardIsTaskSelected('desktopicon') then
    Params := Params + ' -CreateDesktopShortcut';

  if WizardIsTaskSelected('startmenu') then
    Params := Params + ' -CreateStartMenuShortcut';

  Result := Params;
end;

{ ssInstall에서 payload를 해제하고 등록한다. 이 이벤트의 Abort는 설치를 종료한다. }
procedure CurStepChanged(CurStep: TSetupStep);
var
  ScriptPath: String;
  CommandLine: String;
  ResultCode: Integer;
  FamilyName: String;
  FamilyLines: TArrayOfString;
begin
  if CurStep = ssInstall then
  begin
    ExtractTemporaryFile('Ping-Windows-Sideload.cer');
    ExtractTemporaryFile('install-ping-windows.ps1');
    ExtractTemporaryFile('ping-user-data.ps1');
    ExtractTemporaryFile('app.ico');
    ExtractTemporaryFile(MsixFileName);
    ExtractTemporaryFile('dependencies-' + MsixArchitecture + '.txt');
    ExtractTemporaryFiles('{tmp}\Dependencies\' + MsixArchitecture + '\*');
    ScriptPath := ExpandConstant('{tmp}\install-ping-windows.ps1');
    CommandLine :=
      '-NoProfile -ExecutionPolicy Bypass -File "' + ScriptPath + '" ' + GetInstallerParams;

    RegistrationProgress.SetText('앱 등록 중…', '필요하면 인증서 신뢰 단계에서만 관리자 권한을 요청합니다. 자동 시작은 Ping 설정에서 선택할 수 있습니다.');
    RegistrationProgress.Show;
    RegistrationProgress.Animate;
    try
      repeat
        if not ExecWindowsPowerShell(CommandLine, ResultCode) then
          Log('Ping registration process could not start: ' + SysErrorMessage(ResultCode));
        Log('Ping registration exit code: ' + IntToStr(ResultCode));
        if ResultCode = 0 then Break;
        if SuppressibleMsgBox('Ping을 설치하지 못했습니다. 트레이에서 Ping을 종료하고 인증서 승인과 Windows 버전을 확인해 주세요.' + #13#10 +
          '기존 계정과 설정은 유지됩니다. 다시 시도할까요?', mbError, MB_RETRYCANCEL, IDCANCEL) = IDCANCEL then Abort;
      until False;
    finally
      RegistrationProgress.Hide;
    end;
  end;
  if (CurStep = ssPostInstall) and WizardIsTaskSelected('launch') then
  begin
    if LoadStringsFromFile(ExpandConstant('{tmp}\package-family.txt'), FamilyLines) then
    begin
      if GetArrayLength(FamilyLines) <> 1 then Exit;
      FamilyName := Trim(FamilyLines[0]);
      if Pos('YoungminPark.PingWindows_', FamilyName) = 1 then
        if not Exec(ExpandConstant('{win}\explorer.exe'), '"shell:AppsFolder\' + FamilyName + '!App"', '', SW_HIDE, ewNoWait, ResultCode) then
          SuppressibleMsgBox('Ping 설치가 완료되었습니다. 시작 메뉴에서 Ping을 실행해 주세요.', mbInformation, MB_OK, IDOK);
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
  if not ExecWindowsPowerShell(CommandLine, ResultCode) then
    Log('Ping removal process could not start: ' + SysErrorMessage(ResultCode));
  Log('Ping removal exit code: ' + IntToStr(ResultCode));
  if ResultCode <> 0 then
  begin
    SuppressibleMsgBox('Ping을 제거하지 못했습니다. 트레이에서 Ping을 종료한 뒤 다시 시도해 주세요. 계정 보존 파일과 설치 관리자는 유지됩니다.', mbError, MB_OK, IDOK);
    Abort;
  end;
end;
