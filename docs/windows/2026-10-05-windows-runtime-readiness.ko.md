# Windows 실제 수신 런타임 확인

설치된 0.4.10의 Pretendard와 대화 디자인을 유지하면서, 실제 AppCoordinator를 소유 QA 계정으로 실행하는 명시적 진단 경로를 추가했다. 기본 실행의 계정·설정·알림 경로는 유지한다. 진단에서는 설정·거울 위치·보관함·알림 기록의 디렉터리를 별도 지정하고 자동 회신 촬영 권한을 false로 주입한다. 일반 Release에 진단 경로와 타입은 들어가지 않는다. 새 설치 파일을 만들거나 0.4.10 설치본을 교체한 작업은 아니다.

## 실제 결과

- DISPLAY3에서 실제 트레이 추가, 메신저 닫기 시 숨김, 같은 HWND로 다시 열기, 실제 서버 채팅 수신과 공개 알림 진입점의 대화 열기를 확인했다.
- 기존의 서로 다른 A/B 테스트 계정만 복구했다. 유일한 QA 룸을 만들고 멤버가 정확히 두 계정임을 검증했다. 진단 시작 전 빈 룸 목록을 요구한다.
- 합성 3초 MP4를 private storage로 전송했다. 얼굴·화면+얼굴 두 모드에서 공개 영상 알림 진입점으로 플레이어를 열어 실제 네이티브 디코더의 320px 너비, 종료 시 서버 seen 반영, 같은 플레이어 재생을 확인했다. 실제 촬영 결과는 아니다.
- 실제 수신 UI에서도 Pretendard 파일이 로드되며 본문 입력 14 DIP, 사이드바와 템플릿의 폰트 일관성, 별도 아이콘 폰트 유지와 시스템 fallback 대비 다른 글리프 폭을 확인했다. 밝은·어두운 화면을 렌더링했다.
- 수신 코디네이터를 완전히 종료한 뒤 최신 B 세션으로 정리했다. QA 행·알려진 영상 객체를 삭제하고 양쪽 멤버십을 나가 룸 목록이 비었음을 확인했다. 원래 사용자 세션과 백업 2개 파일의 해시·길이는 그대로다.

최종 실제 런타임 검사 31개는 `windows/artifacts/owned-native-a41e1b88cbf1499fb4886fc0cbf1bb91/result.json`에 있다. 별도의 최종 대화 UI 검사 7개와 화면은 `windows/artifacts/ui-shell-3baff9ec184d4a1d964df8a912fde9f9/`다. Core 283/App 339 단위 검사는 각각 `runtime-core-tests.log`, `runtime-app-tests.log`에 있다. 실제 native Debug·일반 Release 빌드 모두 경고·오류 0개다 (`runtime-build.log`, `runtime-release-build.log`). 전체 기존 UI suite를 다시 통과했다는 뜻은 아니다.

## 확인하지 못한 항목과 실패 기록

unpackaged 진단 프로세스의 실제 Windows 알림 등록은 `COMException / 0x8007007E`로 실패했다. OS 큐 검사·셸 알림 클릭·자동 재생·OS 알림 중복 방지 실기는 미확인이다. 이를 가짜 알림으로 대체해 통과시키지 않았다. 공개 알림 처리 진입점과 자동 수신 경로 검증을 구분한다. 설치된 packaged 0.4.10에서 같은 실패가 발생한다는 근거는 아직 없다.

첫 실행 `owned-native-09ffb9ca155d46f0b1cd7ac8bf7fca6a`는 알림 등록 검사에서 실패했고, 두 번째 `owned-native-0202fc2ac4ef4a8994e3c05b829ba568`는 해당 실패 때문에 자동 재생을 기다리다 timeout했다. 두 실행 모두 코디네이터 종료, QA 룸 정리와 원래 사용자 파일 보존을 확인했다. 이후 미확인 항목을 명시하고 공개 진입점의 재생을 별도로 검증했다.

읽기 전용 리뷰의 중요 지적 3개를 반영했다. 시험 자동 촬영을 차단하고, 서버 guard는 클라이언트와 같은 Normalize 결과의 HTTPS·host·port·경로를 검사하며, 개별 OS 알림 정리 실패가 수신 코디네이터 종료를 건너뛰지 못하게 했다. 혼합 URL alias와 HTTP guard 검사는 네트워크 요청 전에 실행한다.

카메라·마이크 실기, Mac 상대 기기, 실제 ARM64, 여러 DPI/고대비 비교와 설치본의 OS 알림·업데이트 실패 복구는 남아 있다. 전체 제품 목표의 완료를 뜻하지 않는다.

## 후속: 실제 알림·자동 재생 확인과 시작 시각 오차 수정

별도의 `-UiSmoke -UiRuntime` 빌드는 설치된 Windows App Runtime에 연결한다. 기본 UI fixture의 self-contained 출력과 디렉터리가 다르며, 일반 MSIX의 설정은 유지한다. 누락된 Insights Resource DLL과 같은 오류는 [Microsoft WindowsAppSDK 이슈6774](https://github.com/microsoft/WindowsAppSDK/issues/6774)에 보고돼 있다. 이 환경 변경 후 실제 Register/OS 큐와 자동 재생을 확인했으므로, 앞선 실패를 설치된 packaged Ping의 알림 실패로 단정하지 않는다.

최초 framework-dependent 실행37개는 `owned-native-c2fc7489e1ab45988dd585c3193aba91`에서 통과했다. 검사를 강화한 후 자동 재생 대기 timeout이 발생해 수신 source와 시각 차이만 추가 기록했다. `owned-native-374cce0bbf3f49e08e920a3cf91e2792`의 실제 영상은 Live이고 age5.530초였지만 서버 created_at이 로컬 앱 시작보다1.953초 앞서 있었다. 기존 `created > appStartedAt` 경계가 신선한 실시간 영상을 차단했다. 실패한 실행들의 소유 데이터 정리와 원래 사용자 파일 보존도 확인했다.

Windows의 실시간 자동 재생·자동 얼굴 회신 시작 경계에 기존30초 시계 오차 상한을 적용한다. age0~60초, 정확한 수신자, Live source와 자동 재생 설정을 유지한다. 자동 회신의 권한·화면 잠듦·카메라 점유·중복·회신 루프 차단도 유지한다. 초기 및 재연결 catch-up은 계속 재생/촬영하지 않는다. Mac 소스는 변경하지 않았다. 실제 촬영을 이 검사에서 사용하거나 검증한 것은 아니다.

두 launch-lag 회귀 테스트의 RED→GREEN을 확인했다. 이후 Core285/App339와 native build가 통과했다. 알림 등록 실패를 수동 재생으로 대체하는 진단 fallback을 제거했고, OS 등록·큐·실제 자동 재생·서버 seen·다시 재생 시 native Playing/시작 위치를 요구한다. 최종39개 결과는 `windows/artifacts/owned-native-8c92cbb6b78247d5a7a299eb4b538978/result.json`이다. OS 알림 정리는 기록한 소유 ID만 제거하고, 원래 세션·백업2개 파일의 해시·길이가 그대로다. 읽기 전용 리뷰에서 환경 설정과 새 정책에 중요 지적은 없었다.

전체 UI304개도 `windows/artifacts/ui-shell-79fbfd455351453d9e17ac57ce894b2c/result.json`에서 통과했다. 실제 Ctrl+V/Shift+Insert, pointer drag/drop, 사진 입력/확대, 인라인 얼굴, 룸 관리, 설정과 첫 사용 안내를 포함한다. 앞선 foreground guard 실패는 이번에 재현되지 않았으며 원인을 게임이나 특정 외부 앱으로 단정하지 않는다. 테스트가 변경한 클립보드는 finally에서 복구한다. Literal shell toast 클릭과 설치본 cold activation은 이 결과에 포함하지 않는다.

시작 경계의 제품 수정은0.4.11 소스에 준비했다. 현재 설치된0.4.10은 아직 이 수정을 포함하지 않는다. 후속 signed 패키지와 실제 설치 확인 전까지 새 버전 배포 완료로 표시하지 않는다.

후속 [0.4.11 설치 후보](2026-10-05-windows-0.4.11-candidate.ko.md)는 동일 소스의 CI, 기존 인증서 서명, x64 패키지 Core 정책과 실제 EXE 업데이트까지 확인했다. 현재 이 PC의 설치본은0.4.11.0 / Status Ok이며 설치된 Core·App·native DLL·Pretendard·OFL은 검증 MSIX와 같다. 원래 세션·백업2개 파일도 그대로다. 위0.4.10 미교체 문구는 앞선 진단 작업의 역사이며 현재 설치 상태는 후보 문서를 따른다.
