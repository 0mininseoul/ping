# Windows 캡처 선택 영역·재촬영 상태 검증

작성일 2026-10-01. 거울 geometry 단계 `e9180f1` 이후의 Task4B다. Task4 전체와 제품 완성 검증은 계속 진행한다.

화면 거울의 view model은 그동안 full-display 캡처 overload를 호출해 Core/native viewport 구현과 연결되지 않았다. 이제 immutable `ScreenCaptureViewport`와 모니터 index를 함께 전달하는 `ScreenMirrorCaptureSelection`을 사용한다. 화면 미리보기와 녹화가 모두 viewport API를 호출한다. 확대를 지원하지 않는 엔진에서는 실패하며 full-display 녹화로 되돌아가지 않는다.

실제 화면 거울은 Enter 시 선택 영역을 먼저 보관하고 편집·파트너 선택을 잠근 뒤 기존 preview의 종료를 기다린다. 종료 중의 반복 Enter는 새 준비나 녹화를 시작하지 않는다. 모니터 값이 그 사이 바뀌어도 녹화 요청에는 보관한 index와 viewport를 전달한다. Recording, Reviewing, Uploading 및 실패 후 clip이 있는 상태에서는 viewport를 수정하지 못한다. 실패 후 전송 재시도는 같은 리뷰 clip을 사용한다.

미리보기 요청에는 선택 영역 revision과 요청 순서를 부여했다. 이전 영역의 frame, 순서가 뒤집힌 frame, 닫힌 창으로 반환된 frame은 화면에 적용하지 않고 반환 파일을 정리한다. 영역이 A→B→A로 돌아와도 이전 A의 frame을 되살리지 않는다. 오래된 실패가 최신 미리보기나 안내를 지우지 않도록 했다. 취소 요청 뒤 정상 반환한 파일도 정리한 후 취소를 전달한다.

얼굴과 화면 거울의 Backspace/Delete는 clip을 삭제하고 Idle 미리보기로 돌아간다. 화면 거울은 이전 preview의 cleanup 이후 새로운 preview session을 시작하며 다음 Enter 전에는 녹화하지 않는다. 현재 Mac의 Backspace는 즉시 재녹화하지만, 승인된 Windows Task4의 “Redo restores editable preview safely through shared camera cleanup”에 따라 화면을 다시 조정할 수 있도록 개선했다. 리뷰 player를 먼저 해제하는 이전 단계의 순서는 유지한다. 닫힌 거울은 녹화·수신자 변경·재촬영을 받지 않는다.

| 검사 | 결과 |
|---|---|
| App Release | 295개 통과, 이전 단계보다 15개 추가 |
| 실제 WinUI 합성 fixture | 104개 통과, 이전 단계보다 12개 추가 |
| 일반 x64 Release native/Core/WinUI | 경고 0, 오류 0 |
| 실제 창 준비 단계 | pending preview cleanup 동안 viewport 고정, 녹화 0회 및 반복 Enter 차단 |
| 실제 창 녹화 요청 | cleanup 전의 모니터·viewport 전달 확인 |
| 실제 창 재촬영 | 리뷰 player 제거·clip 삭제·Idle 복귀, 명시적 Enter 후에만 두 번째 녹화 |
| 실제 창 종료 | owned preview cleanup 후 camera lease 해제 |

추가 App 검사는 viewport API 전달과 immutable snapshot, 반복 Enter·상태별 편집 금지, 미리보기 revision/역순/닫기/취소/오래된 실패, viewport 미지원 시 fallback 금지, 리뷰와 실패 후 redo, 닫힌 Idle 거울의 입력 금지를 확인한다. 미디어 장치를 여는 fake는 없으며 순수 상태 검사에 쓰는 파일은 owned 임시 fixture다.

RED: 재촬영 검사 4개는 기존 구현에서 Idle 대신 Reviewing으로 끝나 실패했다. viewport 계약 검사도 속성이 없는 상태에서 컴파일 실패했다. 실제 UI용 redo 진입점 부재를 확인한 뒤 구현했다. 닫힌 Idle 거울의 CanRecord가 true였던 검사 2개도 실패를 확인한 뒤 수정했다. 기존 fake engines에는 viewport overload를 명시적으로 추가했다. 제품 인터페이스의 미지원 동작을 완화하지 않았다.

새 실제 창 준비 검사는 두 번 실패했다 (`ui-shell-cf9db4bd3a4c40c9b628ce34b70330f2`, `ui-shell-79005ea620854adebe44adfd3e73be2a`). 계측 결과 `stops=0, recordings=0, enterDone=False`였다. 화면 snapshot loop의 비동기 종료를 기다리는 동안 StopPreview 호출이 아직 시작되지 않았는데 검사가 동기 시작을 가정한 문제였다. 제품의 기다림을 제거하지 않고 fake session의 실제 정리 시작 신호를 await하도록 수정했다. 최종 UI 증거는 `windows/artifacts/ui-shell-d59c7bee008941fc86155e41ae66bd59/result.json`이다.

UI fixture는 owned synthetic MP4와 preview/recording 대체 서비스를 사용한다. 실제 창에서 전달한 영역·상태·수명과 MediaPlayer를 확인하지만, fake가 반환한 영상의 픽셀이 실제 화면 crop임을 증명하지 않는다. native crop/composition의 owned MP4 검사는 앞 단계의 증거를 유지한다. 이번 단계에서는 Core/native source를 변경하지 않았으며 이전 Core254/native178 결과를 새 실행 결과로 표시하지 않는다.

Alt-wheel·포인터 추적·pinch·Alt0의 사용자 입력 adapter는 다음 단계다. 현재 700ms snapshot 미리보기는 유지하며 연속 렌더링과 녹화 중 미리보기는 별도로 구현해야 한다. 입력 adapter에서는 [LowLevelMouseProc](https://learn.microsoft.com/en-us/windows/win32/winmsg/lowlevelmouseproc)의 callback timeout/설치 thread message-loop 요구와 [SetWindowsHookEx](https://learn.microsoft.com/en-us/windows/win32/api/winuser/nf-winuser-setwindowshookexw)의 delegate 수명·unhook 요구를 고려한다. busy WinUI thread에 전역 wheel hook을 직접 두지 않는 설계가 필요하며 이번 단계에서 hook을 설치하지 않았다.

얼굴 정사각형 출력과 Ping 창 전체 capture 제외, 전체 캡처 리뷰, 실제 장치·권한·성능·배율 전환·Mac 연동·ARM64·설치 EXE·업데이트 검증도 남아 있다. 실제 카메라·마이크·데스크톱과 사용자 계정 파일·운영 backend는 사용하거나 변경하지 않았다.
