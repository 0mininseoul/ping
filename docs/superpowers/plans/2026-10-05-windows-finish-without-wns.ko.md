# Ping Windows 서버 변경 없는 마무리 실행 계획

**Goal:** 기존 Mac·Supabase·Vercel을 유지하면서 Windows 대화·트레이·재실행 동기화·촬영 안내를 마무리하고 0.4.15 EXE를 생성한다.
**Architecture:** WinUI 3/C#와 기존 native C++ capture, Anonymous Auth/RPC/비공개 Storage를 재사용한다. 프로세스 실행 중 로컬 알림을 사용하고, 종료 중 받은 메시지는 다음 실행 시 대화 기록과 읽지 않음으로 복원한다. WNS는 이번 범위에서 제외한다.
**Execution:** 이 대화에서 순차 구현. 사용자 요청에 따라 자동 테스트·검증용 빌드·린트·화면 검사·별도 리뷰를 수행하지 않는다. EXE 생성에 필요한 컴파일·서명·패키징 및 패키징 과정의 필수 무결성 방어는 유지한다.
**References:** `PING_PROJECT_SPECIFICATION.md`, `docs/superpowers/specs/2026-09-30-windows-parity-design.ko.md`, 최신 Mac `Ping/UI/History/`와 현재 0.4.14 작업 기록.

## 고정 조건

- Mac 소스/API/버전, 기존 backend schema·RPC·webhook·운영 환경은 변경하지 않는다.
- Windows 11 24H2+, 기존 package identity·Publisher·서명 인증서와 익명 계정을 보존한다.
- Pretendard Variable와 한국어·emoji fallback, 원형 얼굴, 둥근 화면 영상, 조용한 전송 완료를 유지한다.
- 종료 중 받은 메시지를 읽음 처리하거나 삭제하지 않는다. 서버 보관 기간 이후 조회를 보장하지 않는다.
- 카메라·마이크 없음은 촬영에만 영향을 주며 채팅·사진·수신·기존 영상 재생은 계속 가능해야 한다.
- 이 계획의 완료는 구현과 설치물 생성이다. 실제 장치 동작 확인·Mac 시각 비교·ARM64 실기·공개 배포는 별도로 남긴다.

## Task 1 — 범위와 사용자 안내

Files: 원래 Windows 설계 문서, 완료 조건 대조 문서, `README.md`, `windows/README.md`.
- [x] WNS·Azure 등록을 현재 목표와 장애 요인에서 제외한다. 과거 검증 기록은 기록 시점의 사실로 보존한다.
- [x] 창 닫기=트레이 실행 유지, 명시적 종료=수신 정지, 다음 실행=서버 기록 동기화의 제품 계약을 문서화한다.
- [x] 실제 장치가 필요한 미확인 항목을 코드 미구현 항목과 분리한다.
Commit: `docs(windows): scope completion to tray reception and launch sync`

## Task 2 — 종료 중 메시지 동기화와 조용한 복원

Files: `windows/src/Ping.Windows.Core/Incoming/IncomingArrivalPolicy.cs`, `IncomingVideoDelivery.cs`, `windows/src/Ping.Windows.App/Bootstrap/AppCoordinator.cs`.
- [x] startup/reconnect catch-up 영상은 개별 배너·자동 재생·자동 회신 없이 기록으로 복원한다.
- [x] 조용히 복원한 영상도 delivery ledger와 notified acknowledgement로 다음 polling의 중복 배너를 막는다. seen은 변경하지 않는다.
- [x] catch-up 채팅과 시작 전 채팅의 로컬 배너를 억제하고 룸 읽지 않음·본문 갱신을 유지한다.
- [x] live 영상·채팅과 사용자 알림 클릭·히스토리 재생의 기존 경로를 보존한다.
Commit: `fix(windows): restore missed messages without notification bursts`

## Task 3 — 트레이·자동 시작·모니터 배치

Files: `App.xaml.cs`, `Bootstrap/AppCoordinator.cs`, `Notifications/NotificationController.cs`, `Setup/SettingsWindow.xaml`; 기존 `MainWindow.xaml.cs`, placement controller/store는 유지.
- [x] Windows StartupTask activation은 대화창을 띄우지 않고 트레이 수신을 시작한다. 수동 실행은 창을 연다.
- [x] SDK activation 조회는 기존 notification registration 이후에만 수행한다. 등록 실패 시 COM 알림 시작 조회를 하지 않는다.
- [x] 자동 시작 중 첫 설정·권한 문제는 사용자가 창을 열었을 때 안내한다.
- [x] 설정에 창 닫기·종료·재실행 수신 설명을 추가한다. 저장된 3번 모니터와 fallback 배치 계약은 보존한다.
Commit: `feat(windows): start quietly in the tray on Windows login`

## Task 4 — 폰트와 UI 세부 표현

Files: `UI/PingTheme.xaml`, `History/HistoryWindow.xaml`, `Setup/SettingsWindow.xaml`.
- [x] 입력 컨트롤의 Pretendard와 본문 14 DIP를 명시해 화면별 fallback 차이를 줄인다. icon font는 교체하지 않는다.
- [x] 읽지 않음 badge를 고대비에서도 강조 색상에 맞는 텍스트 색으로 표시한다.
- [x] Mac sidebar·composer의 구조와 기존 Windows 레이아웃을 유지한다. 사용자 화면 확인 없이 전면 재디자인하지 않는다.
Commit: `fix(windows): align input typography and unread badge contrast`

## Task 5 — 녹화·재생 오류와 Mac 계약

Files: `Capture/CapturePreflight.cs`, `Onboarding/PermissionProbe.cs`, `Bootstrap/AppCoordinator.cs`.
- [x] camera/microphone 없음·권한 거부·초기화 실패와 화면 캡처 오류를 한국어 행동 안내로 정리한다.
- [x] 촬영 실패 안내가 채팅·수신을 막지 않도록 기존 촬영 전 preflight 경계를 유지한다.
- [x] notification 영상 조회 실패 안내를 한국어로 바꾸고 사용자 재생 경로를 유지한다.
- [x] face_only/screen_face, 위치 ratio, 저장 허용·자동 회신·읽음 등의 기존 Mac RPC/data contract를 유지한다. 서버 수정은 하지 않는다.
Commit: `fix(windows): clarify capture and playback recovery messages`

## Task 6 — 0.4.15 설치물과 인계

Files: `Package.appxmanifest`, `.github/workflows/windows-client.yml`, 후보 안내와 실행 기록.
- [x] Windows만 0.4.15.0으로 올린다.
- [x] 수동 workflow에 build_only 입력을 추가해 테스트·smoke를 생략하고 기존 CI 보관 인증서로 x64/ARM64 MSIX·오프라인 EXE를 생성한다. 공개 배포는 끈다.
- [ ] 현재 작업 브랜치의 산출물을 로컬 `windows/dist`에 내려받아 전달한다. 설치·실행 검증을 추가하지 않는다.
- [ ] 구현 완료, 패키징 결과, 미검증 항목을 명시한다. Goal 도구의 기존 paused 상태와 재개 제한도 기록한다.
Commit: `release(windows): package 0.4.15 without automatic validation`

## 사용자가 나중에 할 액션

현재 필수 외부 설정은 없다. 원할 때 화면 디자인 의견을 전달하고, 촬영 확인에는 camera/microphone, 교차 사용 확인에는 Mac을 준비한다. 공개 배포는 사용자가 결정한다. 이전 Goal은 앱에서 재개해야 한다(새 Goal 생성은 unfinished goal 때문에 거절됨).

## 실행 기록

- 2026-10-05: 최신 사용자 범위를 기준으로 작성. 기존 0.4.14 구현을 재사용하며 확인 없는 반복 보강·반복 후보 생성을 피한다.

- Tasks 1–5 구현 commit: cceaa52, 6e3966a, 07bf0d1, 8baf753, a31f0e3. Task 6 packaging source: f06769e.
- 0.4.15 패키징 실행: https://github.com/0mininseoul/ping/actions/runs/37287804018 (build_only=true, 공개 배포 false). 테스트·smoke를 실행하지 않는 산출물 생성 경로다.
- Goal 등록은 기존 unfinished/paused goal 때문에 거절됐다. 도구로 재개하거나 기존 objective를 수정할 수 없으므로 목표 상태를 active로 표시하지 않는다.
