# Windows 화면 확대 입력·창 제외 검증

작성일 2026-10-01. 상태/재촬영 단계 `0108360` 이후 Task4C다. 사용자 요청에 따라 입력 기능과 핵심 사용 흐름을 우선 연결했다.

화면 거울에서 Alt+휠로 1~4배 확대하고 Alt를 누른 채 포인터를 움직여 화면 영역의 중심을 바꿀 수 있다. fractional wheel delta를 유지하며 전체 디스플레이의 물리 좌표를 사용한다. 지원되는 WinUI Scale manipulation도 같은 viewport에 연결했다. Alt+0은 수신자 선택보다 먼저 처리하고, 일반 0은 기존 전체 수신자 선택으로 남긴다. 녹화 준비·녹화·리뷰에서는 확대 입력을 적용하지 않는다. 짧은 한국어 안내와 현재 배율을 표시한다.

전역 휠은 별도의 message-loop thread에 WH_MOUSE_LL을 설치해 처리한다. callback은 한 개의 대기 UI 작업으로 휠 delta를 합치며, UI가 바빠져도 이벤트별 작업을 계속 쌓지 않는다. 활성 디스플레이 state가 변경되면 이전 대기 입력을 버린다. Alt+휠로 받아들인 입력만 처리하고 일반 입력은 hook chain으로 전달한다. 창 내부 Scale gesture와 전역 pointer 추적은 실제 DPI로 좌표를 환산한다. 화면 거울의 Alt+drag는 창 이동과 겹치지 않는다.

33ms 포인터 timer와 gesture/model 구독은 창 종료 시 해제한다. 전역 hook을 해제하고 worker thread Join이 완료된 뒤 창의 shutdown을 완료한다. 전역 hook 시작이 실패하면 창 위의 Alt+휠 입력을 유지하고 안내를 그 범위에 맞춘다. 구현은 [LowLevelMouseProc](https://learn.microsoft.com/en-us/windows/win32/winmsg/lowlevelmouseproc)의 message-loop/timeout 요구와 [SetWindowsHookEx](https://learn.microsoft.com/en-us/windows/win32/api/winuser/nf-winuser-setwindowshookexw)의 callback 수명·unhook 요구를 참고했다.

공통 WindowCaptureExclusion을 메신저, 설정, 룸 관리, 온보딩, 재생, 두 거울, 빠른 전송 HUD, 자동 회신 표시창에 적용했다. 이 9개 앱 창을 만드는 시점에 [WDA_EXCLUDEFROMCAPTURE](https://learn.microsoft.com/en-us/windows/win32/api/winuser/nf-winuser-setwindowdisplayaffinity)를 요청하며 실패를 검사한다. 별도의 보안·DRM 보장으로 취급하지 않는다. 실제 WGC 캡처와 framework popup 포함 결과는 장치 QA에서 확인해야 한다.

| 검사 | 결과 |
|---|---|
| App Release | 295개 통과 |
| 실제 WinUI 핵심 fixture | 120개 통과 |
| 일반 x64 Release | 경고 0, 오류 0 |
| 실제 거울 이미지 | 선택한 viewport로 crop된 owned 파란 이미지 표시, 중심 pixel 검사 |
| 입력 연결 | fractional wheel, 포인터 중심, scale gesture, 안내 배율, Alt0/일반0, 리뷰 편집 차단, 종료 후 입력 차단 |
| native 입력 수명 | 비활성 bounds 상태의 실제 hook 등록·해제 및 message-loop thread Join 확인 |
| 창 제외 | 실제 메신저·설정·거울 HWND affinity 확인 |

RED: 입력 진입점 부재를 확인한 뒤 구현했다. 메신저의 화면 캡처 제외가 적용되지 않은 상태에서는 실제 HWND 검사가 실패했다 (`ui-shell-b0a39a525283480b9874785bef2dde96`). 공통 처리를 적용한 뒤 통과했다. 최종 UI 증거는 `windows/artifacts/ui-shell-098f5b0993d546478d5271b04caa0a0d/result.json`과 `capture-viewport-right.png`다. native hook의 처리된 Alt-wheel 반환만 마지막 Release 빌드에서 변경했으며, 실제 물리 입력은 아직 QA하지 않았다.

입력 fixture는 시스템 timer/hook을 활성화하는 거울 생성 경로 대신 같은 입력 controller에 owned 좌표·gesture를 전달한다. 별도의 native hook 수명 검사는 display bounds를 활성화하지 않아 key state나 mouse packet을 읽지 않는다. 이미지와 리뷰 MP4는 합성 fixture이며 실제 카메라·마이크·데스크톱을 캡처하지 않는다. Core/native DLL source가 바뀌지 않아 기존 Core254/native178 검사를 반복하지 않았다.

남은 캡처 작업은 녹화 중 미리보기와 얼굴 정사각형 출력이다. 이후 전체 캡처 리뷰와 설정·계정·장치·설치 EXE/업데이트 흐름을 마무리한다. 실제 물리 휠·touchpad·touch gesture·다중 모니터·권한·성능·Mac 연동·ARM64 검증은 별도로 남아 있다. 운영 backend와 사용자 계정 파일은 변경하지 않았다.
