# Windows 카메라·마이크 선택 검증

2026-10-01. 설정·기기·설치 계획의 Task 2A 결과다. QR 연결과 최종 EXE는 아직 완료하지 않았다.

## 구현

- 설정의 기기 탭에서 카메라와 마이크를 선택하고 목록을 새로고침할 수 있다. 목록 확인은 장치 정보와 읽기 전용 속성을 조회하며 카메라·마이크를 활성화하거나 녹화하지 않는다.
- 기본값은 사용 가능한 기본 카메라와 Windows 기본 통신 마이크다. 명시적인 마이크 선택은 WinRT ID와 MMDevice endpoint ID를 함께 저장한다. `System.Devices.DeviceInstanceId`와 `PKEY_Device_InstanceId`를 정확히 비교해 대응시키며 문자열을 변환하거나 표시 이름으로 추측하지 않는다.
- 기존 설정 파일에 `Devices` 필드를 추가했다. 필드가 없으면 기존 기본 장치 동작을 유지하고, 기존 룸·외관·소리·자동 재생·저장 설정을 보존한다.
- 카메라 lease를 만들 때 불변 장치 선택을 고정한다. 얼굴 촬영, 화면+얼굴의 카메라 미리보기와 native 녹화, 빠른 전송, 자동 얼굴 회신이 같은 선택을 사용한다. 촬영 중 설정 변경은 다음 lease부터 적용한다. 권한 확인 역시 선택한 장치를 확인한다.
- 목록에서 제거된 장치는 “연결 안됨”으로 표시하며 기본값으로 조용히 변경하지 않는다. 촬영 시 선택한 장치가 없거나 마이크 ID 대응이 바뀌었다면 실패를 안내한다.

## 검증

| 검사 | 결과 |
| --- | --- |
| Core Release 테스트 | 255 통과, 진행 중 lease/다음 lease의 선택 고정 포함 |
| App Release 테스트 | 304 통과, 선택 저장·기존 설정 보존·연결 끊김·합성 native 목록 포함 |
| Native 합성 검사 | 180 통과, 실제 장치 캡처 없음 |
| 실제 WinUI fixture | 143 통과, 실제 ComboBox 선택 저장과 연결 끊김 표시 포함 |
| 정상 x64 Release | native/Core/WinUI 경고 0, 오류 0 |
| DLL exports | 새 `PingCapture_EnumerateMicrophones`와 기존 녹화/미리보기 함수를 포함한 11개 확인 |

WinUI 결과: `windows/artifacts/ui-shell-983d0b5af0dd4c1daf5a163a1af12c15/`. `settings-devices.png`를 직접 확인했다. Native 결과: `windows/artifacts/native-tests-6501242727bb465f8d54f2749b738697/`.

첫 UI 검사는 탭의 view model 목록만 기다린 뒤 아직 로드되지 않은 ComboBox에서 선택해 실패했다. 실제 컨트롤의 로드와 항목 수를 기다리도록 검사 코드를 수정하자 저장과 연결 끊김 검사가 통과했다. 탭 이벤트에서는 내부 ComboBox 선택을 제외해 불필요한 목록 갱신을 방지한다.

## 남은 확인

목록/선택 검사는 합성 장치 ID를 사용했다. 새 MMDevice 열거 경로는 정상 DLL에 컴파일·export됐지만 실제 사용자의 장치 목록을 호출하지 않았다. 실제 장치 열거, 선택한 카메라·마이크로 녹화한 영상/음성, USB 제거와 재연결, 권한 거부는 실기 QA가 필요하다. 합성 검사를 이 실제 결과의 증거로 사용하지 않는다.

다음 Task 2B는 기기 탭에서 최신 세션으로 QR 연결을 제공한다. Mac `exportDeviceHandoff()`가 사용하는 camelCase 필드와 ISO 8601 날짜를 맞추고, 실제 로그인 QR을 검사 로그나 이미지 아티팩트에 남기지 않는다. 계정·업데이트·오프라인 설치 EXE 작업도 전체 목표에 남아 있다.
