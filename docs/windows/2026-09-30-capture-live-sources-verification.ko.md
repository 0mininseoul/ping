# Windows 실제 녹화 경로 연결 검증

작성일2026-09-30. 캡처 플랜 Task3의 두 번째 중간 구현 기록이다. Task3 전체 완료나 실제 장치 QA 통과를 뜻하지 않는다.

## 구현

실제 `RecordScreenFaceMp4V2` 진입점을 전체 세션 vector 수집에서 WGC 화면, 비동기 Media Foundation 카메라, WASAPI 마이크 producer로 교체했다. 세 작업이 준비된 뒤 다음 마이크 packet의 QPC 시각을 공통 시작으로 사용한다. 화면과 카메라 timestamp는 같은 시간축에 놓고, PCM은 장치 sample 위치를 기준으로 연속성을 검사한다. 화면·얼굴은 mapped buffer에서 선택 영역을 바로 작은 top-down BGRA로 만들고, encoder는 프레임마다 바로 압축한다.

화면·카메라별 이력은 최대8개이고 PCM ring은500ms·48,000bytes다. 마이크가 여러 구간을 한꺼번에 전달해도 해당 영상 시각의 과거 프레임을 선택한다. 변경이 없는 정상 화면은 유지할 수 있고, 카메라는 오래된 프레임을 오류로 처리한다. 정적인 검정 화면을 보호된 콘텐츠로 추정하지 않는다. 화면 크기 변경·잘린 buffer·잘못된 stride·오디오 누락·timestamp 오류·시작 timeout은 명시적 실패가 된다.

producer 종료는 모든 source에 먼저 stop을 요청하고 모두 join하는 순서다. WGC callback gate는 진행 중 callback을 기다리고 늦은 진입을 막는다. 카메라는 비동기 reader callback을 차단하고 Flush/OnFlush를 기다린 뒤 source를 종료한다. 마이크는 각 borrowed buffer를 해제한 뒤 다음 packet을 확인하며, client를 해제한 뒤 event를 닫는다. 부분 MP4 삭제와 native 반환은 producer 종료 후 이루어진다.

마이크 QPC와 buffer 규칙은 [Microsoft GetBuffer 문서](https://learn.microsoft.com/en-us/windows/win32/api/audioclient/nf-audioclient-iaudiocaptureclient-getbuffer), [ReleaseBuffer 문서](https://learn.microsoft.com/en-us/windows/win32/api/audioclient/nf-audioclient-iaudiocaptureclient-releasebuffer)를 참고했다. 카메라의 장치 timestamp와 종료는 [DeviceTimestamp 문서](https://learn.microsoft.com/en-us/windows/win32/medfound/mfsampleextension-devicetimestamp), [비동기 source reader 문서](https://learn.microsoft.com/en-us/windows/win32/medfound/using-the-source-reader-in-asynchronous-mode), [Flush 문서](https://learn.microsoft.com/en-us/windows/win32/api/mfreadwrite/nf-mfreadwrite-imfsourcereader-flush)를 참고했다. 장치 timestamp가 없는 카메라는 처음 sample 시간과 QPC 차이를 보정하므로 실제 장치 지연은 별도 검증해야 한다.

## 증거와 한계

| 검사 | 결과 |
|---|---|
| native 합성 입력·실제 MP4 encoder/decoder | Release114개 통과 |
| Core | Release240개 통과 |
| App | Release265개 통과 |
| 일반 x64 Release native/Core/WinUI | 경고0, 오류0 |
| native DLL export | 기존6개 유지 |

native fixture는 실제 WGC/MF/WASAPI 장치 source 파일을 링크하지 않는다. 대체 factory의3개 owned worker를 실제 C 진입점·상태·buffer·writer에 연결한다. 전체 세션 vector 수집을 호출하지 않는 것, frozen viewport 전달,3초 H264/AAC64kbps/30fps 결과, 초반·후반 영상/음성 변화, 시작 실패 시 전체 종료, 취소 시 실제 정리 완료 대기와 부분 파일 삭제를 검사했다. 마이크 parser는 가짜 `IAudioCaptureClient`로 borrowed buffer 해제 순서·silence flag·discontinuity·timestamp 오류를 검사했다. callback gate도 진행 중 작업 종료 대기를 검사했다.

540×304 화면과98×98 얼굴 입력에서 빠른 화면 교체 시 feed가 보유한 할당은 최대5,339,536bytes였다. 양쪽8개 이력이 모두 찬 경우의 상한은5,608,448bytes다. 이 수치는 frame vector capacity와 PCM ring만 포함한다. consumer·생산 중 프레임·합성 결과·codec·GPU·드라이버 및 전체 프로세스 메모리는 포함하지 않는다.

최종 native 증거: `windows/artifacts/native-tests-c767de3bfb5f4cc0af97e9af40b43d6e/`. batched audio의 미래 프레임 선택 실패 RED는 `3883cfde170048e99c486de9e095e7a7`, closed callback 성공 오분류 RED는 `b38ba562`, borrowed audio buffer 해제 전 다음 packet 조회 RED는 `77c6fa`로 남겼다. 기존 소스 문자열30fps 검사는 제거하고 실제 생성 MP4의30/1 frame-rate 검사로 대체했다.

실제 producer 구현은 일반 Release에서 컴파일했다. 실제 카메라·화면·마이크의 capture, driver Flush 종료, 장시간 메모리/성능은 검증하지 않았다. 미리보기와 녹화의 장치 identity 통일, 실제 MF callback의 owned fixture 검증, 기존 화면 snapshot callback 수명 정리와 DPI/확대 UI 연결이 남았다. macOS 소스·실제 사용자 계정 파일·운영 backend는 변경하지 않았다.
