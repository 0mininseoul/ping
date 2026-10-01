# Windows 미리보기·녹화 카메라 선택 연결

작성일2026-10-01. `3d462aa`의 live source 연결 이후 캡처 Task3 중간 작업이다.

기존 WinRT 얼굴 미리보기는 플랫폼이 선택한 카메라를 열고, MF 화면·얼굴 녹화는 첫 번째 카메라를 별도로 열었다. 이제 `CameraLease`마다 카메라의 opaque ID를 한 번 선택한다. WinRT의 `VideoDeviceId`와 native V3의 MF symbolic-link 입력에 이 선택을 전달한다. 미리보기를 종료하고 녹화하거나 재촬영해도 같은 lease에서는 같은 장치를 사용한다. 새 lease는 현재 장치 목록에서 다시 선택한다. 장치 선택 실패·빈 ID·선택한 장치의 활성화 실패를 다른 카메라 선택으로 덮지 않는다.

장치 열거 중 취소해도 실제 열거 작업이 끝나기 전에 카메라 사용권을 해제하지 않는다. native 완료 대기·부분 파일 정리·borrowed lease 유지 규칙은 유지했다. 기존6개 C export를 유지하고 명시적 카메라 ID를 받는 `RecordScreenFaceMp4V3`를 추가했다. 일반 앱의 owned 녹화 경로가 V3를 사용하며, 이전 진입점은 호환 경로로 남았다.

ID의 의미는 [WinRT VideoDeviceId 문서](https://learn.microsoft.com/en-us/uwp/api/windows.media.capture.mediacaptureinitializationsettings.videodeviceid?view=winrt-26100), [MF symbolic-link 문서](https://learn.microsoft.com/en-us/windows/win32/medfound/mf-devsource-attribute-source-type-vidcap-symbolic-link)를 참고했다. 문자열을 장치 이름으로 바꾸거나 분해하지 않는다.

| 검사 | 결과 |
|---|---|
| Core | Release247개 통과 |
| App | Release270개 통과 |
| native | Release116개 통과 |
| 일반 native/Core/WinUI x64 Release | 경고0, 오류0 |
| DLL export | 기존6개 + V3, 총7개 |

추가 Core7개는 한 lease의 중복 선택 방지, 새 lease의 새 선택, 빈/공백/NUL ID 거부, 열거 중 취소 완료 대기, 닫힌 lease 거부를 검사한다. App5개는 미리보기의 선택 재사용, 취소 중 lease 유지, 실패 시 default 카메라 호출 금지, native ID 전달 및 V3 미지원 시 V2로 우회하지 않는 동작을 검사한다. native2개는 실제 V3 진입점에서 대체 factory까지 ID 전달 및 누락된 ID의 source 시작 차단을 검사한다.

native 증거: `windows/artifacts/native-tests-ce707e2dfc9242058b9bca6eb86eaa9c/`. Core/App은 실제 장치 ID 대신 fixture 문자열을 사용한다. native는 장치 factory를 대체하고 실제 encoder·decoder를 사용한다. 실제 장치 열거, 카메라 두 대의 WinRT/MF 활성화, driver 종료는 검증하지 않았다. 마이크의 명시적 공통 identity, MF callback/format owned fixture, 기존 snapshot 수명 정리와 DPI/확대 UI는 남았다. 전체 완성 목표와 캡처 Task3은 계속 진행 중이다.
