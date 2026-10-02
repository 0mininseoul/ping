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

- x64 Release 및 unsigned MSIX 생성: 경고 0, 오류 0. `windows/dist/Ping-Windows-v0.4.0-x64.msix`는 **로컬 검증용이며 설치 가능한 배포물이 아니다**.
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

## 실제 산출물·기기 확인은 아직 필요

GitHub에 기존 서명/공개 구성 Secrets 이름이 존재함을 읽기 전용으로 확인했다. 값은 출력하거나 회수하지 않았다. 로컬 개인키와 ARM64 compiler는 없으므로 기존 CI에서 두 아키텍처를 빌드·서명하고 Inno compiler로 EXE를 생성해야 한다. Secrets 존재만으로 실제 서명 성공을 주장하지 않는다.

자동 승인 검토는 로컬 Inno 설치와 제거 스크립트 전체 교체 명령을 각각 “정책에 의해 차단”했다. 상세 사유는 제공되지 않았다. 같은 명령을 재시도하지 않았고, CI compiler 활용 및 기존 제거 코드의 현재 사용자/데이터 보존 수정으로 진행했다.

새 EXE의 컴파일, UAC 승인/취소, 비관리자 실제 설치·제거·재설치·업데이트, Mac↔Windows 송수신, 카메라·마이크·화면 캡처, ARM64 실기 QA는 아직 수행하지 않았다. 공개 서버는 여전히 `0.3.46`을 제공한다. 새 후보의 공개 릴리즈·웹 다운로드 교체는 별도 단계다.

기준: [Inno lowest privileges](https://jrsoftware.org/ishelp/topic_setup_privilegesrequired.htm), [marquee Animate](https://jrsoftware.org/ishelp/topic_isxfunc_createoutputmarqueeprogresspage.htm), [uninstall Abort](https://jrsoftware.org/ishelp/topic_isxfunc_abort.htm), [MSIX AppData 가상화](https://learn.microsoft.com/en-us/windows/msix/desktop/desktop-to-uwp-behind-the-scenes), [.NET SDK와 MSBuild 버전](https://learn.microsoft.com/en-us/dotnet/core/porting/versioning-sdk-msbuild-vs).
