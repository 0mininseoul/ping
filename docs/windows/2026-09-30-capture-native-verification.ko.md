# Windows 캡처 엔진 확대·합성 검증

작성일: 2026-09-30. 캡처 플랜 Task2의 기록이며 전체 캡처 단계 완료를 뜻하지 않는다.

## 구현

- 확대율·중심 위치를 받는 V2 녹화/미리보기 ABI를 추가했다. 기존 함수 이름은 전체 화면 wrapper로 유지한다. 두 경로 모두 같은 검증된 crop 계산을 사용한다.
- 입력 행 간격과 버퍼 크기를 검사하고, 출력 크기와 할당 범위를 제한한다. 얼굴은 중앙 정사각형을 원형으로 합성하며 가장자리 알파를 처리한다. 기존 얼굴 사각형 늘이기와 영상 내 흰 보더를 Mac 합성 규칙에 맞게 교체했다.
- 화면 메시지는 Mac의 긴 변540px·영상1.2Mbps·모노 AAC64kbps 정책을 따른다. H264 크기는 짝수로 정렬한다. 미리보기는 별도로 최대1920px를 사용한다.
- 관리 코드가 취소 이벤트를 소유하고, 실제 네이티브 호출이 반환된 뒤에 핸들·카메라 사용권을 반환한다. 취소와 실패에서 임시 출력을 지운다. 기존 source 수집 중 취소는 현재 수집 종료를 기다리며, source의 즉각 중단·callback drain은 다음 Task3에서 구현한다.

## 증거

| 검사 | 결과 |
|---|---|
| Core | 240개 통과 |
| App | 266개 통과 |
| native 합성·ABI·실제 codec fixture | 50개 통과 |
| 실제 WinUI 회귀 fixture | 63개 통과 |
| x64 native / 일반 Release | 경고0, 오류0 |
| product DLL export | 기존/V2 진입점6개 확인 |

native fixture는 하드웨어 source 구현을 링크하지 않는다. crop/행 간격/크기/얼굴 합성을 자체 픽셀 배열로 검사하고, 취소된 V2 진입점은 fake source도 시작하지 않는 것을 확인한다. 관리 코드의 지연된 fake native 호출에서 취소 신호가 전달된 뒤에도 작업·핸들·카메라 사용권을 유지하고, 실제 작업 종료 후 파일 정리를 완료하는 것을 검사했다.

실제 Media Foundation sink writer로 테스트 이미지와440Hz PCM을 3초 MP4로 압축하고 다시 읽었다. H264 영상, AAC 오디오 트랙,540×304 크기,3초 길이와 세 지점의 영상 색상을 확인했다. 이 검사는 실제 카메라·마이크 수집을 대체하지 않는다.

압축 후 재읽기 검사에서 처음에는 위쪽이 파랑, 아래쪽이 빨강으로 뒤집혔다. top-down BGRA 입력의 `MF_MT_DEFAULT_STRIDE`를 명시한 뒤 위쪽 빨강·아래쪽 파랑·우하단 얼굴 색상이 유지됐다. signed stride/행 패딩 처리는 [Microsoft Image Stride](https://learn.microsoft.com/en-us/windows/win32/medfound/image-stride)와 [Uncompressed Video Buffers](https://github.com/MicrosoftDocs/win32/blob/docs/desktop-src/medfound/uncompressed-video-buffers.md)를 참고했다.

로컬 증거:

- 방향 오류 RED: `windows/artifacts/native-tests-eb746d9d1eae440fa3f9b5616e881a8f/`
- codec 포함 GREEN와 테스트 MP4: `windows/artifacts/native-tests-5cb54707bcf84c39a24013d15da2512d/`
- 실제 UI: `windows/artifacts/ui-shell-1c4395e4492f47b5b554e5f64f0f5435/`

## 다음 단계

아직 기존 native source가 전체 세션 프레임을 모으므로 메모리 사용 제한과 source 취소/수명 처리를 계속 구현해야 한다. 실제 카메라 버퍼의 방향·행 간격, 전원/장치 변경, 카메라·오디오 공통 녹화 시간도 Task3 범위다.

창의 확대 입력·DPI·화면 비율·위치·앱 창 캡처 제외와 얼굴-only 정사각형 파일은 Task4에서 연결한다. 현재 UI에서 확대 입력을 사용할 수 있다고 주장하지 않는다. Mac 교차 송수신·ARM64·실제 장치·설치 EXE 검증도 남아 있다. macOS 소스, 운영 Supabase와 사용자 계정 파일은 변경하지 않았다.
