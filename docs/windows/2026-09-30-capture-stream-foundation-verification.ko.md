# Windows 순차 녹화 압축 기반 검증

작성일2026-09-30. 커밋 `6fec6b3` 시점의 캡처 플랜 Task3 중간 구현 기록이다. 아래의 최신 프레임 1개·compatibility provider 설명은 이 커밋의 상태다. 이후 실제 녹화 진입점 연결과 프레임 이력 변경은 [live source 검증 기록](2026-09-30-capture-live-sources-verification.ko.md)을 참고한다. 실제 장치 수집 경로 전체의 메모리 제한이나 Task3 완료를 뜻하지 않는다.

## 구현과 적용 범위

`Mp4SinkWriter`는 프레임 provider에서 화면·얼굴·PCM 한 구간을 받아 즉시 합성하고 압축한다. 영상과 오디오를 동일한100ns 시간축으로 자르고,30fps의 반올림 나머지를 각 구간에 반영해 총3초가 된다. 누락된 PCM을 침묵으로 채우던 처리를 제거했다. 입력 실패·예외·취소·encoder 시작 실패에서 provider를 종료하고 부분 파일을 지운다. 성공한 결과만 유지한다.

정리 순서는 encoder 객체 해제 → provider의 source 정리와 callback 종료 대기 → Media Foundation/COM 종료 → 실패 파일 삭제다. COM이 먼저 종료되는 오류를 비동기 fixture로 재현하고 수정했다. 느린 encoder가 입력을 무제한으로 받지 않도록 sink writer의 기본 throttling을 유지한다. 이 동작은 [Microsoft sink writer 문서](https://learn.microsoft.com/en-us/windows/win32/medfound/mf-sink-writer-disable-throttling)를 참고했다.

`BoundedRecordingBuffer`는 이미 crop/resize한 화면·얼굴의 최신 프레임을 각각 하나만 보유하고, 오디오는48kHz 모노16bit·500ms 고정 ring으로 받는다. 이전 프레임은 consumer가 사용하는 동안만 살아 있다. 늦거나 미래인 프레임, source 크기 변경, 오디오 sample 누락, ring 초과, 시작 timeout을 명시적 오류로 처리한다. 정상 길이 뒤에 큰 vector 할당을 숨기는 경우도 거부한다. 닫힌 buffer는 늦게 들어온 publish를 받지 않는다.

540×304 화면과98×98 얼굴 fixture에서 buffer가 보유한 할당은 최대743,056bytes다. 이 수치는 buffer의 frame vector capacity와48,000bytes 오디오 ring을 합한 것이며, consumer snapshot·생산 중 프레임·합성 결과·codec/GPU/드라이버 메모리를 포함하지 않는다. 실제 앱 전체 사용량의 측정치로 해석하면 안 된다.

`CapturePixelView`는 실제 바이트 범위·첫 행 위치·signed stride를 검사한 뒤 선택 영역을 직접 작은 packed top-down BGRA로 만든다. 음수 행 간격·행 패딩·범위 밖 crop·잘린 버퍼·입출력 alias·과도한 출력 크기를 검사했다. 정상 검정 픽셀도 허용한다. 기존 합성과 미리보기 crop은 이 함수를 사용한다.

**이 커밋 시점의 product 녹화 진입점은 전체 세션 vectors를 수집하고 compatibility provider를 거쳐 압축했다.** 새 bounded feed는 synthetic provider에서 검증됐다. 실제 WGC/MF producer와 공통 녹화 시작 시각, callback drain, 장치 선택, 취소 연결은 후속 단계의 범위다.

## 검증

| 검사 | 결과 |
|---|---|
| native synthetic / 실제 MP4 encoder·decoder | Release96개 통과 |
| Core | Release240개 통과 |
| App | Release266개 통과 |
| 일반 x64 Release native/Core/WinUI | 경고0, 오류0 |

fixture는 실제 화면·카메라·마이크 source 파일을 링크하지 않는다. 자체 입력으로 생성한 MP4를 실제 Media Foundation decoder로 읽어 초반/후반 영상 변화와 오디오를 검사했다. 디코딩 PCM RMS는 초반1413.33, 후반7069.67이며 sample 시간이 단조롭게 증가하고 영상의 마지막 초까지 도달했다. 기존 확대/방향/H264/AAC64kbps/3초 결과도 함께 회귀 검사했다.

지연된 가짜 source callback을 사용해 writer가 callback 정리를 기다리는 동안 반환하지 않고, 정리가 끝나면 부분 파일을 삭제하는 것을 확인했다. 이것은 실제 WGC/MF callback 구현 검증이 아니라 provider 계약 검증이다. 실제 장치 통합에서 같은 보장을 검사해야 한다.

로컬 증거:

- 숨겨진 큰 vector 할당 RED: `windows/artifacts/native-tests-49fc431aec594852ab4dcb6837f62417/`
- 정리 전 COM 종료 RED: `windows/artifacts/native-tests-aa8c96c8359a452c9dbe44550f34d1e5/`
- 최종 Release96 및 MP4: `windows/artifacts/native-tests-9f4bd0ab7053441ca7bd202114b26a8a/`

빌드 스크립트는 Windows PowerShell5.1에서 공백과 마지막 역슬래시가 있는 compiler target 경로를 잘못 전달했다. 동일 명령이 PowerShell7에서는 통과했고,5.1의 단일 property 조회로도 문제를 재현했다. 마지막 구분자를 `/`로 전달한 뒤5.1의 일반 Release도 통과했다. 이 수정은 `154f548`에 기록했다. AAC 중복 압축률 수정은 `2828917`과 앞선 native 검증 기록을 참고한다.

다음 작업은 실제 bounded producer와 product 진입점 연결이다. 이후 DPI/확대 입력·거울 창·얼굴 정사각형 출력, 전체 캡처 리뷰, 계정/장치/설정/EXE 및 실제 장치 QA를 계속 진행한다. 운영 backend, macOS 소스와 실제 사용자 계정 파일은 변경하지 않았다.
