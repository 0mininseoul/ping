# Windows 거울창 배율·위치·리뷰 검증

작성일 2026-10-01. 마이크 선택 단계 `101df4a` 이후의 캡처 Task4A다. Task4 전체와 제품 완성 검증은 진행 중이다.

기존 거울은 XAML에서 DIP 크기를 요청하면서 AppWindow에는 같은 값을 물리 픽셀로 전달했다. 고배율 화면에서는 내용이 잘렸고 화면 거울은 모니터 비율과 무관하게 16:9였다. Mac `MirrorWindow.swift`와 `MirrorView.swift`를 기준으로 얼굴은 200DIP 원형, 화면은 실제 디스플레이 비율을 유지하는 긴 변 480DIP와 16DIP 모서리로 바꿨다. 작은 작업 영역에서는 전체 거울이 들어가도록 줄인다. Mac 소스와 배포 설정은 변경하지 않았다.

`CaptureMirrorWindowHost`가 공통 크기·위치·클립·drag 수명을 소유한다. border/title 없는 OverlappedPresenter를 사용하고 항상 위에 표시한다. [ResizeClient](https://learn.microsoft.com/en-us/windows/windows-app-sdk/api/winrt/microsoft.ui.windowing.appwindow.resizeclient?view=windows-app-sdk-1.8)에 현재 DPI로 환산한 클라이언트 픽셀 크기를 전달한다. ClientToScreen/GetWindowRect로 숨은 외곽 offset을 보정하며 실제 client를 기준으로 네이티브 원형/둥근 region과 XAML composition clip을 적용한다.

DPI·디스플레이·작업 영역 변경 알림과 XamlRoot 변경에 반응한다. 거울 배경을 끌어 다른 모니터로 이동할 수 있고 파트너 선택 chip은 drag에서 제외한다. 이동 중에는 송신 위치만 갱신하고 놓았을 때 작업 영역에 맞춰 위치를 저장한다. 창 종료 시 subclass, pointer, AppWindow와 XAML 구독을 해제한다. 실제 사용자 drag와 서로 다른 DPI 모니터 사이의 전환은 별도 장치 QA가 필요하다.

기존 로컬 위치 설정은 작업 영역 기준으로 유지한다. 송신 좌표는 [DisplayArea.OuterBounds](https://learn.microsoft.com/en-us/windows/windows-app-sdk/api/winrt/microsoft.ui.windowing.displayarea.outerbounds?view=windows-app-sdk-1.8)의 전체 디스플레이 기준으로 계산해 작업 표시줄 때문에 상대 위치가 달라지지 않게 했다. 음수 모니터 origin도 처리한다. 기존 메시지 경계의 top→bottom Y 변환은 한 번만 적용한다.

두 거울 HWND에는 [SetWindowDisplayAffinity](https://learn.microsoft.com/en-us/windows/win32/api/winuser/nf-winuser-setwindowdisplayaffinity)의 WDA_EXCLUDEFROMCAPTURE를 설정하고 결과를 검사한다. 이번 단계는 거울에만 적용했다. 다른 Ping 창 전체 제외와 실제 WGC 결과 확인은 남아 있다. 이 API를 보안·DRM 보장으로 취급하지 않는다.

리뷰의 MediaPlayer를 종료한 뒤 임시 파일을 삭제하도록 순서를 맞췄다. 송신 실패 시 실제 player와 clip을 유지한다. 원형 안에서 긴 안내가 잘리는 것을 렌더 결과로 확인해 짧은 한국어 안내로 바꾸고 세부 설명은 tooltip에 둔다. 송신 성공은 기존 fade-out을 유지한다.

| 검사 | 이번 단계 결과 |
|---|---|
| App Release | 280개 통과 |
| 일반 x64 Release native/Core/WinUI | 경고 0, 오류 0 |
| 실제 WinUI 합성 fixture | 92개 통과 |
| 실제 거울 client / 현재 배율 | 200% 환경에서 DIP·픽셀·디스플레이 비율 일치 |
| 실제 owned HWND 작업 영역 변경 | 영역 밖으로 이동 후 설정 변경 알림에 client clamp |
| 실제 리뷰 player | 합성 MP4 자연 크기와 재생 시간 진행 확인 |
| 실패·종료 | upload 실패 후 리뷰 유지, player 종료 후 clip 삭제 및 camera lease 해제 |

기존 Core254/native178 검사는 이번 단계에서 소스를 변경하지 않았으며 이전 마이크 단계의 증거를 유지한다. 순수 layout의 100/150/200%·portrait·ultrawide·작은 작업 영역 검사를 실제 다중 모니터 QA와 혼동하지 않는다.

RED: 새 위치 계약이 없는 상태에서 App 테스트가 컴파일 실패했고, 실제 얼굴 client가 padding 없이 200DIP이어야 한다는 검사가 기존 구현에서 실패했다 (`ui-shell-112b6ecf18b745a58dabc038c5772460`). SDK presenter의 공식 border/title 속성이 false여도 raw HWND style에 DLGFRAME 비트가 남는 환경을 확인해 잘못된 raw-style 기대를 제거했다. 클라이언트 geometry, 실제 region, 공식 presenter 상태는 계속 검사한다. 기존 4개 source-string 검사를 실제 창의 크기·clip·리뷰·종료 동작 검사로 교체했다.

최종 UI 증거는 `windows/artifacts/ui-shell-e64209322c7244e3aebc9113e07c1939/`와 `result.json`이다. 얼굴/화면 리뷰 PNG는 XAML 안내·클립·배치를 확인하는 자료다. RenderTargetBitmap에서 media 영역은 비어 보일 수 있으므로 PNG를 영상 픽셀 재생 증거로 사용하지 않는다. 영상은 실제 MediaPlayer의 자연 크기와 시간 진행을 따로 확인했다.

fixture는 owned 창과 합성 MP4 및 대체 preview/recording 서비스를 사용한다. 실제 카메라·마이크·데스크톱·사용자 계정과 운영 Supabase를 사용하지 않았다. 남은 Task4는 Alt 확대·포인터·pinch·reset, 녹화 viewport 고정, 다시 촬영 시 편집 미리보기 복귀, 녹화 중 미리보기, 얼굴 정사각형 출력 및 Ping 창 전체 제외다. 이후 전체 캡처 리뷰, 실제 장치·권한·성능·Windows↔Mac 연동, ARM64, 설치 EXE와 업데이트 검증을 이어간다.
