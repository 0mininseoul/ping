# Windows 비동기 카메라 reader 종료 검증

작성일2026-10-01. 카메라 sample 처리 `607f5e6`의 후속 캡처 Task3 작업이다.

`CameraReaderSession`이 실제 비동기 MF SourceReader와 callback, sample normalizer, Flush 완료 event를 소유하도록 분리했다. 실제 카메라 source와 합성 MP4 fixture가 같은 session 구현을 사용한다. 한 session에서 한 번만 초기화·시작하며 영상 stream만 선택한다. sample과 source event 실패는 한 번 전달하고 추가 sample 요청을 멈춘다. 처리 callback의 예외는 COM 경계 밖으로 던지지 않는다.

종료는 callback gate 차단·진행 중 callback 대기 → 모든 stream Flush → actual OnFlush 완료 대기 → OnFlush callback 종료 대기 → reader/callback 해제 → publisher 참조 해제 순서다. 실제 카메라의 media source는 이 reader 종료 뒤 Shutdown하고, 이어서 MF/COM을 종료한다. 늦게 들어오는 callback은 닫힌 gate를 확인하며 event/state를 강한 참조로 유지한다. callback은 실패를 반환하고 owner thread가 종료하므로 callback 안에서 session 종료에 재진입하지 않는다.

비동기 ReadSample 규칙은 [Microsoft 비동기 reader 문서](https://learn.microsoft.com/en-us/windows/win32/medfound/using-the-source-reader-in-asynchronous-mode), Flush 종료 규칙은 [Flush 문서](https://learn.microsoft.com/en-us/windows/win32/api/mfreadwrite/nf-mfreadwrite-imfsourcereader-flush)와 [OnFlush 문서](https://learn.microsoft.com/en-us/windows/win32/api/mfreadwrite/nf-mfreadwrite-imfsourcereadercallback-onflush)를 참고했다. 실제 driver 초기화와 Flush 대기를 시간 제한으로 끊고 카메라 사용권을 버리는 경로는 만들지 않았다. driver 응답 지연은 실제 장치 QA에서 확인해야 한다.

| 검사 | 결과 |
|---|---|
| native Release |167개 통과, /W4 /WX |
| 일반 x64 Release native/Core/WinUI | 경고0, 오류0 |
| 관리 코드/UI | 이번 단계에서 변경 없음; 기존 Core247/App270/WinUI63 기록 유지 |

새14개 검사는 fixture가 앞서 생성한 `synthetic-screen-face.mp4`를 실제 MF 비동기 reader로 연다. normalized32×32 얼굴 callback을 진행 중 상태로 유지한 뒤 다른 thread에서 종료를 요청한다. callback이 끝나기 전 반환하지 않고 actual Flush를 마친 뒤 반환하는 것, 종료 후 추가 영상과 publisher 참조가 남지 않는 것, 중복 시작/닫힌 session 재시작 차단을 검사했다. 반복 decoder callback80개 이상에서 단조로운 시간과 EOS 실패 전달을 검사했다. 처리 consumer의 취소는 한 번 전달하며 추가 읽기를 멈추고, consumer 예외도 terminal 오류로 전달한다. reader 초기화 실패도 검사한다.

최종 증거: `windows/artifacts/native-tests-c29dc3dfa9684962b89db49abb41b037/`. 계약 파일이 없는 상태에서 검사 실패를 확인한 뒤 구현했고, SDK include 순서와 signed stream 상수 변환 오류를 수정해 엄격한 native 빌드로 검증했다.

fixture는 `CameraReaderSession.cpp`와 `CameraSampleNormalizer.cpp`를 직접 링크한다. 카메라/화면/마이크 장치를 활성화하는 source 파일은 제외한다. actual reader와 Flush 동작 검증은 합성 파일 source에 대한 증거이며 실제 카메라 driver 검증을 대신하지 않는다. 마이크 identity 통일, 거울 DPI/확대 입력·촬영 중 미리보기·얼굴 정사각형 출력, 전체 캡처 리뷰, 실제 장치/Windows와Mac 연동 및 설치 EXE가 남았다. 운영 backend와 실제 사용자 계정 파일은 변경하지 않았다.
