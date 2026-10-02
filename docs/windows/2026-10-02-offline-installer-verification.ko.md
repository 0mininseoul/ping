# Windows 0.4.0 설치 후보 검증

앱·Microsoft Windows App Runtime을 EXE에 함께 넣는 설치 구성으로 변경했다. 기존 MSIX identity/Publisher와 서명 인증서를 유지한다. Windows만 `0.4.0.0`으로 올렸으며 Mac 버전은 변경하지 않았다.

## 구현

- EXE에 x64/ARM64 MSIX, 런타임, 인증서, 설치·제거·데이터 보존 스크립트를 포함하고 OS 아키텍처에 맞는 파일만 해제한다. 설치 중 패키지를 다운로드하지 않는다.
- 현재 사용자의 일반 권한으로 앱을 등록·실행한다. 필요한 인증서 신뢰만 별도 UAC 요청을 사용한다. 관리자 권한으로 전체 설치를 실행하면 중단한다. 자동 시작은 앱 설정을 사용한다.
- identity/버전/아키텍처, 원래 Ping 인증서, Microsoft 런타임 서명을 확인한다. EXE 빌더는 네이티브 캡처 DLL과 pinned 프로젝트 공개 연결 설정도 검사한다. 서명 없는 검증 패키지로 EXE를 만들지 않는다.
- 실제 등록 단계의 marquee, 실패·재시도·취소를 제공한다. 실행 중인 Ping은 트레이에서 먼저 종료해야 한다. 설치 실패를 완료로 표시하지 않는다.
- 제거는 현재 사용자에게만 적용한다. MSIX의 가상화된 최신 계정·설정과 일반 AppData 파일을 제거 전에 `%LOCALAPPDATA%\PingWindows\PreservedData\<family>`에 보존하고, 패키지 제거 후 `%LOCALAPPDATA%\Ping`에 복원한다. 재설치는 기존 파일을 덮어쓰지 않는다. 공유 인증서·런타임과 직접 저장한 영상은 유지한다.
- 설치 관리자는 사용자 데이터를 일괄 삭제하지 않는다. 익명 계정 제거는 앱 설정에서 별도 확인을 거친다. 보존 파일에는 인증 토큰이 있으므로 공유하거나 로그에 첨부하지 않는다.
- Release도 로컬에서 검증한 C++ MSBuild + .NET SDK 분리 빌드를 사용한다. 새 GUID 출력으로 이전 산출물 혼입을 피한다. CI Secrets의 PFX와 공개 인증서 일치 및 공개 anon/publishable key만 포함하는지 검사한다.

## 확인한 결과

- 첫 로컬 x64 Release 및 unsigned MSIX 생성: 경고 0, 오류 0. unsigned 검증본은 `windows/artifacts/local-x64-034d1d9011894dfd94a42bc84349bc79/`에 남아 있다. 최종 `windows/dist/` 파일은 아래 CI의 서명된 후보로 교체했다.
- MSIX 내용: `0.4.0.0`/x64 identity, 네이티브 캡처 DLL, 공개 `Supabase.json`, 업데이트 helper, 자체 포함 .NET 런타임. UI 진단/ZXing/사용자 세션 파일 없음.
- `smoke-release.ps1 -Platform x64 -AllowUnsigned`, `package-sideload-release.ps1 -Platform x64 -AllowUnsigned`: 성공. unsigned ZIP에는 검증용이라는 안내를 포함한다.
- OS PowerShell 5.1의 `test-installer-payload.ps1`: 기존 공개 서명 MSIX로 정상 오프라인 검증, 버전 불일치 거부, 의존성 경로 탈출 거부 3개 통과. 임시 복사본만 사용하며 앱 등록·인증서 추가·실행은 하지 않았다.
- `test-user-data-preservation.ps1`: 최신 가상화 계정 우선, 일반 설정 보존, 재설치 기존 계정 보호, 제거 후 복원, 한정된 경로 처리/탈출 거부 5개 통과. 합성 문자열을 담은 owned 폴더만 사용했다.
- PowerShell 구문 검사와 `git diff --check`: 성공. 이전 기능 milestone의 Core 271/App 312/WinUI fixture 165/native synthetic 180 통과 기록은 각 검증 문서에 있다.

## milestone 검토와 수정

`1a7a258..6202d28`을 독립 리뷰어가 읽기 전용으로 검토했다. Critical 없음, 중요한 결함 2개를 한 번의 수정 단계로 처리했다.

1. `ssPostInstall`의 `Abort`는 Setup을 종료하지 않는다는 Inno 계약을 확인했다. 등록을 `ssInstall`로 옮기고 해당 OS 아키텍처의 임시 payload를 먼저 명시적으로 해제한다. 이 이벤트에서 실패·취소하면 Setup이 종료되며, 파일 설치와 성공 페이지로 진행하지 않는다. 앱 실행은 실제 패키지 등록 및 wrapper 설치가 끝난 `ssPostInstall`에서 수행한다. 실제 EXE 취소 동작은 CI 컴파일 이후 설치 QA에서 확인해야 한다.
2. 공유 룸의 같은 채팅 ID가 저장 계정 A와 B에 각각 미읽음이어도 전역 알림 파일로 인해 B 알림이 사라지던 문제를 재현했다. UID에 따라 분리된 알림 파일을 bootstrap 완료 전에 선택한다. A/B 각각 알림 표시 + 동일 A 재시작 중복 방지의 임시 파일 검사가 실패 → 통과했다. 새 알림 파일도 제거·재설치 보존 대상이다. 소유자를 모르는 기존 전역 알림 ID를 임의 계정에 귀속시키지 않는다.

최종 재검사: Core **271**, App **308** 통과, x64 Release/MSIX 빌드 경고·오류 0. App 수는 312에서 구형 온라인/관리자 설치 및 특정 빌드 인자 철자를 강제하던 소스 문자열 검사 5개를 실제 PowerShell payload/보존 검사와 패키지 확인으로 대체하고, 계정 알림 회귀 검사 1개를 추가한 결과다. 웹 다운로드 검사는 개발 manifest 대신 실제 공개 `latest-version.txt`와 EXE 존재 여부를 사용한다. 공개 링크를 미배포 버전으로 바꾸지 않았다.

## 실제 EXE 산출물

[CI 37017447762](https://github.com/0mininseoul/ping/actions/runs/37017447762)는 `d0d4cdf`에서 성공했다. Core 271/App 308/보존 fixture/서명 payload 검증 후 x64·ARM64를 빌드하고 원래 인증서로 서명했다. Inno compile도 성공해 `PingSetup-v0.4.0.exe`를 생성했다. 로컬로 내려받은 두 MSIX의 OS 서명 `Valid`/원래 thumbprint, 버전/CPU/pinned 공개 설정/.NET/update helper를 다시 확인했다. EXE는 `213867430` bytes, SHA-256 `61773bf420841065ca09ff1fa90bb5747ad9a1501a1ef50a9b75cf4d2b28b9d8`이며 외부 EXE 자체는 `NotSigned`이다. 내부 앱의 서명과 외부 EXE 공인 서명을 혼동하지 않는다.

첫 CI 37016762383은 기존 서명 payload fixture에서 실패했다. CI가 공개 인증서를 CurrentUser에만 신뢰 등록하고 있었고, 로컬은 LocalMachine에도 등록되어 있었다. MSIX의 machine trust 요구에 맞춰 ephemeral CI runner의 LocalMachine TrustedPeople에도 같은 공개 인증서를 등록하고 엄격한 검증 기준을 유지했다. 다음 CI는 해당 검사와 실제 앱 서명/EXE 생성까지 통과했다. 로컬 PC의 신뢰 저장소나 기존 Secrets는 변경하지 않았다.

아티팩트 업로드만 수행했으며 공개 릴리즈/웹 교체 입력은 false였다. 원래 인증서의 개인키를 로컬로 회수하거나 새 인증서로 교체하지 않았다. [설치 후보 안내](2026-10-02-release-candidate-guide.ko.md)에 실행 파일과 남은 실제 QA를 기록했다.

## 실제 기기 확인은 아직 필요

GitHub에 기존 서명/공개 구성 Secrets 이름이 존재함을 읽기 전용으로 확인했고, 이어서 실제 CI 서명이 성공했다. 값은 출력하거나 회수하지 않았다. 로컬 개인키와 ARM64 compiler는 없으며 실제 ARM64 PC 실행은 아직 필요하다.

자동 승인 검토는 로컬 Inno 설치와 제거 스크립트 전체 교체 명령을 각각 “정책에 의해 차단”했다. 상세 사유는 제공되지 않았다. 같은 명령을 재시도하지 않았고, CI compiler 활용 및 기존 제거 코드의 현재 사용자/데이터 보존 수정으로 진행했다.

EXE 컴파일은 확인했다. UAC 승인/취소, 비관리자 실제 설치·제거·재설치·업데이트, Mac↔Windows 송수신, 카메라·마이크·화면 캡처, ARM64 실기 QA는 아직 수행하지 않았다. 공개 서버는 여전히 `0.3.46`을 제공한다. 새 후보의 공개 릴리즈·웹 다운로드 교체는 별도 단계다.

기준: [Inno lowest privileges](https://jrsoftware.org/ishelp/topic_setup_privilegesrequired.htm), [marquee Animate](https://jrsoftware.org/ishelp/topic_isxfunc_createoutputmarqueeprogresspage.htm), [uninstall Abort](https://jrsoftware.org/ishelp/topic_isxfunc_abort.htm), [MSIX AppData 가상화](https://learn.microsoft.com/en-us/windows/msix/desktop/desktop-to-uwp-behind-the-scenes), [.NET SDK와 MSBuild 버전](https://learn.microsoft.com/en-us/dotnet/core/porting/versioning-sdk-msbuild-vs).

## 2026-10-02 실제 PC 설치 검증 착수
- 사용자 설치·제거·재설치 및 3초 로컬 녹화 허용. 기존 등록된 Ping/실행 프로세스/물리 데이터 없음, Windows 26200 x64 일반 권한, 기존 인증서 신뢰 있음.
- 실제 EXE 첫 설치 exit3: ssInstall 등록 실패에서 올바르게 중단. 직접 동일 서명 MSIX 등록은 성공(0.4.0.0, Status Ok). EXE 전용 원인 아직 미확정. 이후 사용자 Esc로 화면 제어 중단; 실기 영상/재설치 미검증.
- PS5.1 기본 인자의 PSScriptRoot가 비어 Join-Path가 param binding 단계에서 실패함을 설치 ValidateOnly와 제거 스크립트에서 재현. 경로 기본값을 본문으로 옮기고 제거의 미사용 인증서 기본식 제거. owned signed fixture 기본 경로 검사 RED→GREEN, payload 검사 4개 통과.
- EXE 등록/제거에 ExecAndLogOutput와 종료 코드 기록 추가: 스크립트는 토큰/프로필 내용을 출력하지 않는다. 원인 없이 설치 검증을 완성으로 표시하지 않는다.

## 2026-10-03 지정 모니터 및 실제 캡처 사전 확인
- 사용자 요청 DISPLAY3(세로형) 시험 위치 지원. `windows/scripts/test-ui-smoke.ps1 -MonitorDeviceName '\\.\DISPLAY3'`로 지정. 별도 진단 빌드에서만 모든 초기 창의 표시 영역을 선택하며 배포 앱에는 이 override를 포함하지 않는다. 없는 장치를 지정하면 주 모니터로 조용히 대체하지 않고 실패한다.
- 실제 메신저·설정 창의 디스플레이 식별 검사를 먼저 추가해 RED(주 모니터) 확인 후 지정 위치 구현. WinUI 167개 GREEN, 아티팩트 `windows/artifacts/ui-shell-5eb57bf6978a436692a284f7d5875208`. 얼굴/화면 거울·재생·자동 회신 UI 합성 검사를 같은 세로 모니터에서 통과. 합성 UI 영상은 실기 카메라 녹화 증거가 아니다.
- 실제 서명된 0.4.0 DLL을 읽어 네이티브 화면 사전 확인 수행. PowerShell의 DPI-unaware 호스트는 주 모니터의 가상/물리 크기가 달라 code6 실패. 앱 manifest와 같은 PerMonitorV2 스레드에서 재현 시 화면 SelfTest code0. smoke 도구도 같은 스레드 DPI를 사용하고 종료 시 이전 컨텍스트를 복구하도록 수정.
- DISPLAY3의 native index를 EnumDisplayMonitors/GetMonitorInfo로 찾은 뒤 3초 로컬 화면+얼굴 녹화 호출: code4(PingCaptureNoCamera), 실제 MP4 미생성. Windows Camera/Image present 장치도 없음. 웹캠 연결 여부를 사용자에게 질문했으며 소프트웨어 통과로 대체하지 않는다. 운영 룸/다른 사람에게 테스트 영상을 보내지 않았다.
