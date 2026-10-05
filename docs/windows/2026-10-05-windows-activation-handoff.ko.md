# Windows 시작 중 알림 전달 경계 수정

0.4.11 설치 이후 남은 cold activation 흐름을 조사했다. `Program.OnActivated`가 처리기 유무를 잠금 밖에서 읽었으므로, 앱 생성자가 처리기를 등록하고 대기 목록을 비운 뒤 늦게 알림이 대기 목록에 들어갈 수 있었다. 이 항목을 다시 비울 기회가 없어 대화/재생 진입점이 실행되지 않는다.

## 재현과 수정

실제 Windows 실행 파일의 `AppActivationArguments`와 `Program.OnActivated`를 사용한다. 진단에서 대기 목록 잠금을 잡아 발행 스레드를 멈추고, 앱 생성자와 같은 처리기 등록·목록 비우기 순서를 실행한 후 잠금을 푼다. 구현을 복제한 mock으로 대체하지 않는다.

- 수정 전: delivered0 / initial0 / late1, exit1. `windows/artifacts/activation-red-8fc1ced8e1974288a64fc7978722eda0/result.json`.
- 수정 후: 처리기 확인과 대기 목록 추가를 같은 잠금 안에서 실행한다. 콜백 호출은 잠금 밖에 유지한다. 새 queue/추가 지연/다시 시도는 넣지 않았다.
- 수정 후: 시작 전 보관, 멈춘 발행 스레드와 등록의 경계, 동시 시작 전달20,000회, 실행 중 전달1,000회 검사4개가 통과했다. lost0/late0, exit0. `windows/artifacts/activation-green-5f4744331449445889e65dde42f01ba4/result.json`.
- 반복 가능한 명령은 `windows/scripts/test-activation-handoff.ps1`이다. 실제 스크립트 실행도 `activation-02d3c07551dd41caabe99a0b3dae1eba/result.json`에서 통과했다. 일반 동시 실행만으로는 수정 전 문제가 재현되지 않아, 위 잠금 경계를 제어하는 재현 검사를 추가했다.
- Core285/App339와 실제 native Debug/Release 빌드가 통과했다. 로그는 `windows/artifacts/activation-*-tests.log`, `activation-green-build.log`, `activation-release-build.log`이다.

진단 명령·타입은 `PING_UI_SMOKE`에서만 컴파일된다. 이 진단은 `new App()` 전에 끝나며 계정/서버/카메라/사용자 창을 열지 않는다. 원래 설치본의 계정 세션·백업2개 파일은 최초 기준과 그대로임을 별도로 확인했다. macOS 소스·폰트·UI·Supabase 계약은 변경하지 않았다.

정상 Release DLL 메타데이터에서도 진단 타입0개를 확인했다 (`windows/artifacts/activation-release-verification.json`). 읽기 전용 리뷰는 새 잠금 경계와 실제 RED/GREEN 재현에 중요 지적이 없었다. OS 클릭·종료 중 dispatcher·하드웨어/설치 항목은 이 리뷰의 검증 범위에 포함하지 않았다.

## 적용 범위

이것은 실제 프로그램의 동시 전달 경계 검사다. OS 배너를 클릭한 결과나 설치본 cold activation 송수신 완료를 뜻하지 않는다. [Microsoft 알림 시작 안내](https://learn.microsoft.com/en-us/windows/apps/develop/notifications/app-notifications/app-notifications-quickstart)는 COM으로 시작된 알림을 `NotificationInvoked`에서 처리해야 할 수 있음을 설명하므로, 시작 종류를 보는 검사와 실제 OS 클릭 검증을 구분한다.

현재 설치본과 배포 EXE는 검증한0.4.11을 유지한다. 이 추가 수정은 소스에 준비하며 다음 후보에 포함한다. 작은 수정마다 새 설치 파일을 만들지 않는다. 사용자는 현재 Mac이 없다고 확인했으므로 가능한 Windows 검증을 계속한다. 카메라·마이크·Mac 실제 상대, ARM64, DPI·고대비/Mac 화면 대조, 설치본의 OS 알림 클릭과 업데이트 실패 복구는 전체 목표의 남은 항목이다.
