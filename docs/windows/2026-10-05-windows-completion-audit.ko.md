# Windows 완성 조건 대조 —0.4.14

> 2026-10-05 범위 변경: 아래 0.4.14 근거는 과거 기록이다. 사용자는 WNS를 제외하고 서버 변경 없는 트레이 수신·재실행 동기화를 선택했다. 종료 상태 신규 push는 더 이상 미완료 조건이 아니다. 자동 검증도 중단했으며 현재 구현 계획은 [서버 변경 없는 마무리 계획](../superpowers/plans/2026-10-05-windows-finish-without-wns.ko.md)을 따른다. 실제 장치·Mac 확인은 사용자 요청 시 수행할 미확인 항목으로 구별한다.

사용자의 목표는 최신 Mac과 같은 메신저 동작·디자인, Windows에 맞는 상호작용과 정상 EXE 설치다. 테스트 수나 설치 후보 생성만으로 목표를 완료로 축소하지 않는다.

현재 HEAD의 제품 소스는0.4.14이며 설치 상태는0.4.14.0 / Ok, 앱은 종료 상태다. 패키지 원본은 `cde5133432f0ccf63d056ee0d4bd56e201f16401`의 CI37270892324다. 최근 `origin/main`은 `5b21c1962de83d1e0d6c08ba8619802cbd53280b`이며 현재 작업과 `Ping/`, `project.yml` 차이가 없다. Mac13+/Swift6/glass wrapper/기존 startup 구현을 변경하지 않았다.

## 사용자 요구사항별 근거

| 요구사항 | 현재 근거 | 완료 판단 |
|---|---|---|
| 1. Mac과 같은 UI/UX | Mac 소스를 참고한 대화·설정·온보딩, 원형 얼굴·화면 영상·기본 송신 룸, Pretendard. 실제 WinUI313개 결과와 light/dark 렌더가 존재하고 최근 후보의 해당 UI/폰트 소스 차이는 없다 | 구현·Windows fixture 검증 진행. 실제 Mac 비교, 실제 장치 입력·녹화와 종료 상태 신규 push가 남아 있어 전체 완료 아님 |
| 2. 설치 EXE |0.4.14 EXE와 서명된 x64/ARM64 MSIX 생성, 실제 x64 업데이트, 원래 계정 파일7개와 설치 파일 해시 보존. 이전0.4.13 제거·재설치 및 실제 등록 거부 후0.4.14 재실행 확인 | 설치물 전달과 확인한 x64 경로는 완료. ARM64 기기 실행과 설치 중간 rollback은 미확인 |
| 3. 기존 Windows 개발 활용 판단 | 초기 저장소 분석에서 WinUI/C++ 통신·캡처 기반을 유지하고 주 대화 화면을 재구성. 현재 코드와 독립 native/portable 검사가 존재 | 기술 선택과 재구성 구현 완료. 이전 데모 화면으로 최종 디자인을 대체하지 않음 |
| 4. 최신 Mac 기능·디자인 참고 | 최신 main과 Mac 소스 차이 없음. 대화, 링크·사진, 인라인 얼굴, 캡처 viewport·리뷰, 계정·기기·설정에 원본 계약 반영 | 소스 참고는 확인. 실제 Mac↔Windows 기능 매트릭스와 기기 handoff 실기는 미확인 |
| 5. 메신저 목적에 맞는 Windows 개선과 정상 기능 | 트레이·Alt 단축키·대화창 재사용·룸 관리, 송수신·읽음·반응·사진·영상, 연결 복구·계정 보존. 실제 소유 QA 계정의 서버/수신 런타임 검사 존재 | 구현과 확인한 경로는 진행됐으나 촬영 실기·설치본 OS 클릭·종료 상태 신규 push 등 남은 요구사항 때문에 전체 완료 아님 |

관련 근거: [초기 분석](2026-09-30-repository-audit.ko.md), [캡처 milestone](2026-10-01-capture-milestone-verification.ko.md), [실제 서버 대화](2026-10-05-windows-native-live-qa.ko.md), [수신 런타임](2026-10-05-windows-runtime-readiness.ko.md), [0.4.14 설치 후보](2026-10-05-windows-0.4.14-candidate.ko.md), [설치 거부·재시도](2026-10-05-windows-deployment-retry.ko.md).

실제 WinUI 결과 `windows/artifacts/ui-shell-3a18b08d48624df1835e7f86994d0721/result.json`은 Success=true/313개, 실제 소유 계정 수신 결과 `windows/artifacts/owned-native-8c92cbb6b78247d5a7a299eb4b538978/result.json`은 Success=true/39개를 다시 확인했다. 후자는 합성3초 MP4를 사용한다. Core285/App348은 실제 UI 전체 실행을 대체하지 않는다. 앱 클릭 처리기 호출·COM fixture·실제 OS 알림 클릭도 각각 구별한다.

## 범위에서 제외한 종료 상태 신규 알림 (기존 분석 기록)

Windows `AppCoordinator`의 Realtime/polling은 실행 중인 프로세스에 속하고 `NotificationController`는 `AppNotificationManager.Show`로 로컬 알림을 만든다. 현재 소스·manifest에는 WNS 채널 생성·등록·push activation이 없다. 백엔드 `device_tokens`의 platform 제약도 `ios`, `watchos`, `macos`만 허용한다. 따라서 Windows 앱이 완전히 종료된 후 도착한 신규 메시지의 원격 배너는 미구현이다. 기존 배너를 클릭해 종료된 앱을 여는 활성화 검증과는 별도 요구사항이다.

Microsoft [WNS 시작 지침](https://learn.microsoft.com/en-us/windows/apps/develop/notifications/push-notifications/push-quickstart)에 따르면 Azure/Entra 앱 등록과 packaged 앱의 PFN 매핑이 필요하다. 매핑 요청은 Microsoft의 주 단위 처리 대상으로 설명돼 있다. 현재 확인할 Ping package family는 `YoungminPark.PingWindows_512qqyksm04b8`이다. 필요한 입력은 기존 등록의 AppId, tenant 정보와 서비스 principal ObjectId 및 매핑 여부다. 비밀 자격 증명은 서버 쪽에 보관해야 하며 Windows 설치물·로그·채팅에 넣지 않는다.

Azure 등록·매핑의 기존 위치를 사용자에게 문의했다. 현재 로컬 설정에서 WNS 연결을 확인하지 못했다. 다른 프로젝트를 만들거나 운영 DB 제약을 임의 변경하지 않았으며 Microsoft로 이메일을 보내지 않았다. 실제 등록과 서버 연결을 확보한 뒤 채널 등록·사용자/설치 소유권·계정 변경/채널 만료·영상/채팅/초대 routing·종료 상태 배너·클릭을 완결해야 한다. 계속 상주하는 로컬 polling으로 이 항목을 완료 처리하지 않는다.

## 다음 실기 검증의 제약

- 0.4.14 설치본의 OS 알림 클릭과 기존 배너 cold activation: 앞선 Computer Use가 Esc로 중단돼 화면 입력 재개 답변 대기. 원래 계정 복원 guard는 준비했으며 실행하지 않았다.
- 얼굴/화면+얼굴3초와 빠른 전송·자동 얼굴 회신: 카메라가 없다는 사용자 응답이 있고, 실제 마이크·드라이버·A/V 동기화 결과도 아직 없다. 합성 MP4 검사를 촬영 성공으로 표시하지 않는다.
- Mac↔Windows 송수신·시각 비교·기기 handoff: 현재 Mac이 없다는 사용자 응답. 실제 상대 기기 결과가 필요하다.
- ARM64 실행, 혼합 DPI/고대비/물리 입력, MSIX staging 중간 실패 복구와 앱 내 업데이트 전체 경로: 기존 fixture·서명 검사·EXE 성공 범위를 넘어서는 실기 검증이 남아 있다.

확인된 새 결함 없이 후보를 반복 생성하지 않는다. 0.4.14 이후에는 새 사용자 범위에 필요한 변경과 설치물만 생성하고 위 실기 검증을 자동 진행하지 않는다. 현재 목표에서는 WNS나 장비 미확인만을 이유로 코드·설치물 완료를 무한 대기하지 않는다.

## 현재 장치와 푸시 구성 재확인

Windows의 present Camera class 장치는0개, AudioEndpoint는7개였다. 오디오 출력과 마이크 입력을 구별하기 위해 검증된 x64 MSIX에서 native DLL을 격리 추출하고 설치된 DLL과 SHA-256이 같음을 확인한 뒤, 실제 `PingCapture_EnumerateMicrophones`를 호출했다. 반환은0(정상), 활성 capture endpoint는0개였다. 장치를 활성화하거나 소리를 녹음하지 않았다. 이는 실제 입력 마이크가 없어 촬영/음성 검증을 진행할 수 없다는 현재 근거이며, 마이크 녹화 성공을 의미하지 않는다.

설치 경로의 DLL을 외부 PowerShell 진단에서 직접 로드한 첫 시도는 `0x80070005`로 실패했다. 권한/보안 설정을 바꾸지 않았고 소유한 MSIX 추출본으로 위 읽기 전용 확인을 수행했다. 일반 설치 앱의 DLL 로드가 실패한 결과로 해석하지 않는다.

GitHub Secret 이름만 조회해 WNS/Azure/Entra/Windows push에 해당하는 구성 이름0개를 확인했다. 비밀 값은 읽지 않았고 기존 Azure 등록이 다른 위치에 없다고 단정하지 않는다. 설정 위치에 관한 사용자 답변은 대기 상태다. 장치 및 읽기 전용 진단의 근거는 `windows/artifacts/device-availability-0414-ba63f5ff2580431da66836d0b19f0b73`의 `result.json`, `environment.json`이다. 원래 사용자 계정과 화면 입력은 사용하지 않았다.
