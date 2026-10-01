# Windows 캡처 milestone 검증

기준 `de6d791`부터 `72eb61b`까지의 캡처 구현을 완료했고, 독립적인 읽기 전용 리뷰 한 번에서 조치할 Critical/Important 결함이 발견되지 않았다. 다음 설정·계정·기기·EXE 구현으로 진행한다. 전체 제품 완성을 의미하지 않는다.

완료된 구현은 현재 디스플레이 DPI에 맞는 얼굴 200DIP/화면 긴 변 480DIP 거울, 실제 화면 비율, Alt 확대·포인터 이동·초기화, 녹화 시작 시 viewport 고정, 선택한 카메라·마이크 소유권, bounded WGC/MF/WASAPI 캡처와 MP4 스트리밍, 녹화 중 같은 합성 프레임 표시, 얼굴 영상 중앙 정사각형 저장, 리뷰/재녹화/종료 정리와 명시적 Ping 창 9종의 화면 캡처 제외다.

| 검사 | 결과 |
|---|---|
| Core/App Release | 254 / 297 통과 |
| 네이티브 Release owned fixture | 180 통과 |
| 실제 WinUI 합성 fixture | 129 통과 |
| 정상 x64 Release와 검증용 MSIX | 경고·오류 0, 성공 |
| 정상 네이티브 DLL | 기존 export 포함 10개, V5 확인 |
| 정상 관리 assembly | UiSmokeRunner/FaceVideoCropSmoke fixture 타입 제외 확인 |
| 전체 milestone 구현 리뷰 | 조치할 Critical/Important 결함 없음 |

최근 아티팩트와 상세 확인은 [녹화 미리보기·정사각형 저장 보고서](2026-10-01-capture-live-preview-square-verification.ko.md)에 기록했다. 기존 카메라 reader/sample, 마이크 선택, snapshot, DPI geometry, viewport state/input 보고서도 유지한다.

리뷰는 소스와 기존 검사 근거를 평가했으며 장치나 빌드를 다시 실행하지 않았다. 모든 fixture는 소유한 합성 이미지·영상·오디오 또는 대체 장치 factory를 사용했고 실제 사용자 세션·데스크톱·카메라·마이크·운영 Supabase를 사용하지 않았다. 검증용 MSIX는 서명되지 않아 공개 설치 배포물이 아니다.

실제 카메라/마이크/드라이버/권한/A/V 동기화, 다중 모니터 DPI와 물리 입력, framework popup 제외, 성능, Mac 상호 송수신, ARM64 실행과 설치·업데이트 QA는 남아 있다. 전체 목표는 계속 진행 중이다.
