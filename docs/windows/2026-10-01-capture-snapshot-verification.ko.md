# Windows 화면 미리보기 수명·선택 영역 검증

작성일2026-10-01. 캡처 Task3 중간 작업이다.

화면 미리보기와 자체 검사를 기존 `MonitorCapture`에서 녹화와 공유하는 WGC session/callback 구현으로 옮겼다. callback은 stack 변수나 borrowed event를 참조하지 않는다. 정리 시 gate로 진행 중 callback을 기다리고 늦은 작업을 막은 뒤 구독·session·frame pool을 닫는다. 완료 event와 결과는 callback이 소유한 상태에 묶인다. 초기화·timeout·취소·예외에서도 같은 정리 순서를 사용한다. 새 COM/WinRT apartment는 소유한 경우에만 종료하고 이미 있는 STA apartment는 빌려 사용한다.

선택 영역은 GPU staging map에서1920px long-side 이하의 top-down BGRA로 직접 변환한다. 전체 원본 화면을 CPU vector로 복사한 뒤 확대하지 않는다. BMP 진입점은 이미 선택된 결과에 확대를 다시 적용하지 않는다. 정상적인 검정 화면을 보호된 콘텐츠로 판단하던 추정도 제거했다.

content 크기와 texture의 BGRA 형식·extent·sample·mip·array를 확인한 뒤 읽는다. display 크기 변경은 실패로 처리한다. content는 같지만 texture 저장 크기가 바뀐 경우 staging texture를 다시 만들어 `CopyResource`의 서로 다른 크기 입력을 피한다. 선택 영역과 signed-stride 검사는 기존 `CapturePixelView`를 공유한다.

사용하지 않는 전체 세션 수집 구현 `MonitorCapture.cpp`·`CameraFrameSource.cpp`와 내부 선언을 제거했다. 기존 public C export는 유지한다. 화면 자체 검사도 native 완료를 기다리는 동안 호출 스레드를 막지 않게 했다. onboarding의 DLL은 비동기 native 호출이 끝난 후 해제한다.

| 검사 | 결과 |
|---|---|
| native fixture | Release126개 통과 |
| App | Release270개 통과 |
| Core | 앞선 camera 선택 단계의 Release247개 통과, 이후 Core 변경 없음 |
| 일반 x64 Release native/Core/WinUI | 경고0, 오류0 |
| 실제 WinUI 소유 fixture | Debug63개 통과 |

native에 추가한10개 검사는 실제 preview C 진입점의 viewport 전달, BMP 방향/픽셀·중복 확대 방지·취소 전달 및 실제 소스가 사용하는 texture 계약을 검사한다. 실제 WGC source는 대체 함수로 제외한다. 새 경로를 연결하기 전 `1465197ea57a40e387e1bbb39e3637c3`에서116개 뒤 preview 검사 실패를 확인했다. 최종126개는 `windows/artifacts/native-tests-9cdf920bdf134298b224e29d2b1e2ae6/`에 남겼다.

App의 추가 검사는 대기 중인 가짜 native 자체 검사를 별도 호출 스레드에서 시작한다. 수정 전 호출이 반환하지 않아 timeout RED가 났고, 수정 후 호출 스레드는 반환하며 native 작업은 완료까지 계속 기다리는 것을 확인했다. 옛 namespace 문자열 검사는 제거했다. 실제 native 컴파일과 texture/BMP 동작 검사를 사용한다.

WinUI 증거: `windows/artifacts/ui-shell-74f506cf74d24ea7ba51eee9be3ac5c3/`. 이 fixture는 자체 UI와 합성 preview만 사용하며 실제 화면·카메라·마이크·사용자 계정에 접근하지 않는다. 기존 메시지 UI와 거울 창 종료/재입력/지연된 preview 정리 동작이 회귀하지 않는지를 확인한다. 실제 WGC callback 전달, GPU driver 종료, 다중 모니터/DPI 전환과 장치 성능은 아직 검증하지 않았다.

다음은 MF 카메라의 buffer/format/callback을 소유 입력으로 검증하고, 마이크 identity를 통일하는 작업이다. 이후 거울 DPI/확대 입력·실제 촬영 미리보기·얼굴 정사각형 출력·전체 캡처 리뷰, 계정/설정·서명된 설치 EXE와 실제 장치 QA가 남았다. 전체 완성 목표와 Task3은 진행 중이다.
