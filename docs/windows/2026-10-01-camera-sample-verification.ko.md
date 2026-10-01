# Windows 카메라 sample 방향·buffer·시간 검증

작성일2026-10-01. 캡처 Task3의 카메라 sample 처리 단계다. 실제 카메라 driver 검증이나 Task3 완료를 뜻하지 않는다.

`CameraSampleNormalizer`를 실제 카메라 callback에 연결했다. 실제 MF sample의 단일 buffer를 받아2D buffer의 scanline/pitch/extent 또는 raw buffer의 signed stride를 검사한다. 중앙 정사각형을 작은 top-down BGRA 얼굴 frame으로 직접 만든다. 여러 buffer를 전체 원본 크기의 contiguous buffer로 복사하는 경로는 사용하지 않는다. RGB32 video 형식과 첫 sample의 source 크기를 고정하고, 잘린 buffer·format/크기 변경·잘못된 rotation을 실패로 처리한다. 버퍼는 성공/실패 경로에서 해제하고 해제 실패도 출력 성공으로 숨기지 않는다.

MF의0/90/180/270도 회전은 중앙 crop과 resize에 함께 적용한다. 별도 원본 크기의 회전 buffer를 만들지 않는다. 회전 방향은 [Microsoft MFVideoRotationFormat 문서](https://learn.microsoft.com/en-us/windows/win32/api/mfapi/ne-mfapi-mfvideorotationformat)의 반시계 규칙을 사용했다. 실제2D buffer의 pitch와 scanline 정의는 [Lock2DSize 문서](https://learn.microsoft.com/en-us/windows/win32/api/mfobjects/nf-mfobjects-imf2dbuffer2-lock2dsize)를 참고했다.

유효한 장치 QPC timestamp를 우선한다. 장치 timestamp가 없는 경우에만 첫 sample에서 source 시간과 QPC의 차이를 보정한다. 이후 callback 도착 지연으로 sample 시간을 덮지 않는다. 잘못된 timestamp 타입·범위·시계 역행·signed overflow는 실패로 처리한다. 실패한 sample은 frame이나 clock/format 상태를 새로 확정하지 않는다.

| 검사 | 결과 |
|---|---|
| native Release |153개 통과, /W4 /WX |
| 일반 x64 Release native/Core/WinUI | 경고0, 오류0 |
| Core/App/WinUI | 이전247/270/63개 통과 기록 유지; 이번 단계에서 관리 코드·UI 변경 없음 |

추가27개 검사는 actual MF raw/2D buffer를 직접 만들어 positive/negative stride, 중앙 crop, 회전, source clock 보정·overflow·역행, 잘못된 형식과 잘린 buffer를 검사한다. 직사각형 signed-stride 입력의90/180/270도 회전도 별도로 검사한다. MF2D buffer는 [MFCreate2DMediaBuffer](https://learn.microsoft.com/en-us/windows/win32/api/mfapi/nf-mfapi-mfcreate2dmediabuffer)로 만들며 실제 카메라를 활성화하지 않는다. 기존 실제 MP4 encoder/decoder와 녹화 진입점 회귀 검사도 함께 통과했다.

최종 증거: `windows/artifacts/native-tests-9b2d02fac28a443c81de729ac78de21f/`. 먼저 normalizer 계약이 없는 상태의 검사 실패를 확인한 뒤 구현했다. fixture는 `CameraSampleNormalizer.cpp`를 직접 링크하지만 실제 device source 파일은 제외한다. actual MF buffer 검증을 실제 카메라 driver 검증으로 해석하면 안 된다.

다음은 카메라의 actual 비동기 SourceReader/Flush callback을 소유한 합성 MP4 입력으로 검사하는 작업이다. 마이크 identity·거울 DPI/확대 입력·얼굴 정사각형 출력·실제 장치/Windows와Mac 연동·설치 EXE 작업도 남았다. 운영 backend와 실제 사용자 계정 파일은 변경하지 않았다.
