# Windows 녹화 마이크 선택 통일 검증

작성일 2026-10-01. 카메라 reader 종료 작업 `0480ab7` 이후의 캡처 Task3 단계다.

얼굴 녹화의 WinRT 기본 오디오 장치와 화면·얼굴 녹화의 WASAPI 통신용 기본 마이크가 서로 달라질 수 있었다. 이제 통신용 기본 capture endpoint를 한 번 선택하고, 그 endpoint의 장치 인스턴스 속성과 일치하는 활성 WinRT 오디오 인터페이스를 찾는다. `CameraLease.MicrophoneSelection`이 WinRT 인터페이스 ID와 MMDevice endpoint ID 쌍을 보관한다. 같은 lease에서 기본 장치가 바뀌어도 선택을 다시 하지 않으며 새 lease는 다시 선택할 수 있다.

WinRT `AudioDeviceId`에는 인터페이스 ID를, 네이티브 `IMMDeviceEnumerator.GetDevice`에는 endpoint ID를 그대로 전달한다. ID의 형식이나 표시 이름을 해석하지 않는다. 공통 속성은 `PKEY_Device_InstanceId`와 `System.Devices.DeviceInstanceId`이며 SDK와 공식 문서의 property key는 동일하다: `78C34FC8-104A-4ACA-9EA4-524D52996E57`, property256. 인스턴스 문자열은 Ordinal 비교한다. 일치하는 활성 인터페이스가 없거나 둘 이상이면 실패한다. 다른 기본 장치를 다시 선택하는 fallback은 없다.

이 연결 방식은 [Core Audio 장치 속성](https://learn.microsoft.com/en-us/windows/win32/coreaudio/device-properties), [DeviceInstanceId 속성 정의](https://learn.microsoft.com/en-us/windows/win32/properties/props-system-devices-deviceinstanceid), [WinRT 추가 장치 속성](https://learn.microsoft.com/en-us/windows/apps/develop/devices-sensors/device-information-properties)을 참고했다. 실제 드라이버가 반환하는 두 속성 값의 일치 여부는 장치 QA에서 확인해야 한다.

네이티브 identity 조회는 COM apartment, endpoint/property store, GetId 문자열 및 PROPVARIANT를 소유하고 읽기 전용으로 조회한다. 오디오 장치를 활성화하지 않는다. 비활성 endpoint, 누락·잘못된 타입·빈 인스턴스 속성, 접근 거부, 잘못되거나 부족한 출력 버퍼를 검사한다. 부족한 버퍼에는 잘린 ID나 부분적인 쌍을 반환하지 않는다. 조회 취소는 실제 native/WinRT 조회가 종료된 뒤 반환하므로 카메라 사용권을 먼저 해제하지 않는다.

새 `PingCapture_RecordScreenFaceMp4V4`가 카메라 ID와 마이크 endpoint ID를 모두 요구하고 owned source factory까지 전달한다. 일반 앱의 OwnedScreenFaceCaptureEngine은 이 경로를 사용한다. 선택한 ID가 없거나 새 API가 없으면 다른 기본 장치로 녹화하지 않는다. 기존 V2/V3는 호환용으로 유지한다. 녹화 중 연결 해제·권한 오류는 기존 source 실패/cleanup 경로로 처리한다.

| 검사 | 결과 |
|---|---|
| Core Release |254개 통과 |
| App Release |280개 통과 |
| native Release /W4 /WX |178개 통과 |
| 일반 x64 Release native/Core/WinUI | 경고0, 오류0 |
| 실제 WinUI 합성 fixture |64개 통과 |
| DLL exports | 기존7개 유지, V4/identity 조회 추가:9개 |

추가 검사는 Core7개, App10개, native11개다. Core는 ID 쌍 연결, 비활성/미일치/중복 인터페이스, invalid ID, lease별 선택 고정과 취소 완료 대기를 검사한다. App은 preview 선택 재사용, 선택 실패/취소 때 native 시작 방지, endpoint ID 전달, V4 미지원 시 fallback 금지 및 native 조회 대기를 검사한다. Native는 가짜 IMMDevice/IPropertyStore로 실제 identity export를 호출하고 실제 V4→owned synthetic source→MP4 writer 경로를 검사한다. fixture는 실제 장치 factory를 교체하며 카메라·마이크·화면을 캡처하지 않는다.

RED: Core 마이크 계약/lease 속성과 App 장치 bound 계약 부재, native identity/V4 링크 오류를 확인했다. native 테스트의 누락된 string include와 Windows `small` 매크로 이름 충돌도 수정했다. 최종 native 증거는 `windows/artifacts/native-tests-f154c3b6765e438b9e7763004a015638/`, UI 증거는 `windows/artifacts/ui-shell-f73d115ccd8c4ee58249379deee73f9c/`다.

기존 auto-reply 합성 lock 검사는 두 번 실패했다 (`ui-shell-4e138c70e1d5488f98f1345da8a82862`, `ui-shell-715a387bfcec493d83dd48c7ce78a5ca`). 처음부터 차단된 환경에서는 추가 lock이 새 interruption generation을 만들지 않는 것이 올바른 동작이다. fixture의 깨어 있음 가정을 없애고 owned 합성 state를 허용 상태로 명시한 뒤 lock 시 generation 증가와 unlock 후 동일 generation 유지를 검사하도록 수정했다. 제품의 잠금·절전 방어는 변경하지 않았다.

Task3의 bounded source/encoder 구현 및 장치 선택 계약 검사는 확보했다. 다음은 Task4의 거울 DPI·비율·확대 입력, 촬영 중 미리보기와 얼굴 정사각형 출력이다. 전체 캡처 리뷰, 실제 장치·권한·장치 변경·driver 지연·성능, Windows↔Mac 연동, ARM64, 설치 EXE와 업데이트 검증은 남아 있다. 운영 backend와 사용자 계정 파일은 변경하지 않았다.
