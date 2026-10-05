# Windows 사진 드롭과 붙여넣기

Mac 기준은 `5b21c1962de83d1e0d6c08ba8619802cbd53280b`의 `RoomTimelineView.swift` 사진 드롭이다. Windows에서는 대화 타임라인과 작성창 전체에 사진을 끌어놓고, 입력창에 Ctrl+V·Shift+Insert로 클립보드 사진을 붙여넣는다. 사진 메뉴에도 붙여넣기 진입점을 제공한다. 일반 텍스트 붙여넣기는 기본 TextBox 동작을 유지한다.

Mac 드롭의 즉시 전송과 달리 Windows는 기존 사진 첨부 방식에 맞춰 먼저 48 DIP 미리보기와 파일명을 보여주고 Enter로 문구와 함께 전송한다. 실수로 보낸 사진을 줄이고 전송 실패 시 첨부와 문구를 그대로 다시 보낼 수 있게 하는 Windows UX 결정이다. 캡션은 Pretendard 12 DIP, 입력은 기존 14 DIP를 따른다. 드롭 대상은 Mac처럼 16 DIP 라운드와 반투명 accent 표시를 사용한다.

## 처리와 수명

- 파일 선택·드롭·클립보드 이미지는 동일한 reader와 기존 이미지 업로드/채팅 서비스에 연결한다. 사진은 한 장씩 첨부한다. 원본 파일은 수정하거나 제거하지 않고 소유한 임시 복사본을 만든다.
- 파일 입력은 기존 저장소 계약의 JPEG·PNG·HEIC·HEIF·GIF·WebP와 15 MB 제한을 따른다. 로컬 디코더가 읽을 수 없는 사진은 한국어 오류를 표시하고 기존 첨부를 유지한다. 모든 PC의 HEIC 코덱 설치를 뜻하지 않는다.
- 클립보드 bitmap은 PNG로 정규화한 뒤 15 MB를 검사한다. 압축 전 4K BMP에 업로드 제한을 적용하면 정상 스크린샷을 거부하므로 원본 stream은 별도 256 MB, 디코더는 64 MP로 제한한다.
- 비동기 읽기 중에는 이전 문구만 전송되지 않도록 전송을 잠시 막는다. 새 입력·취소·룸 전환은 이전 읽기를 무효화한다. 늦게 끝난 읽기가 새 룸에 붙지 않는다. 파일 선택기가 열린 동안 룸을 바꿔도 같은 방어를 적용한다.
- 룸별 작성 중 첨부는 해당 룸에 남는다. 성공한 전송·첨부 취소·교체·계정 detach는 쓰지 않는 소유 복사본과 미리보기를 정리한다. 전송 중인 복사본은 send ticket이 끝날 때까지 보호한다. 실패하면 복사본과 문구를 유지하고 기존 서비스가 실패한 원격 업로드를 best-effort 제거한다.

## 검증

기존에 사진 드롭 진입점이 없다는 실제 WinUI 실패를 먼저 확인했다. 구현 후 DISPLAY3 실제 WinUI 297개 검증이 통과했다. 새 사진 입력 범위는 원본 해시 보존·미리보기·캡션·지원하지 않는 파일·15 MB 초과 파일·실패와 재전송 payload·성공/취소 후 복사본 정리·텍스트와 bitmap 붙여넣기·늦은 읽기·룸별 작성·계정 정리를 포함한다.

추가로 4K 원본 BMP의 잘못된 크기 거부를 실패로 확인한 뒤 수정했다. 이미지 전용 클립보드의 실제 Ctrl+V와 Shift+Insert 입력, 소유한 진단 source의 실제 마우스 드래그에서 대화 Drop handler까지 확인했다. Shift+Insert는 기본 TextBox가 먼저 처리하므로 입력 연결을 PreviewKeyDown으로 옮겼다. 사진 외에 Enter·Shift+Enter·IME 작성 정책은 기존 회귀 검사를 유지한다.

렌더와 진단 결과는 `windows/artifacts/ui-shell-4664a4c58ff840cb9ec117084549aa35/`다. 사진과 대화는 소유한 fixture다. 클립보드 검사에서는 기존 형식을 메모리에 복사하고 WinRT DataPackage로 복원하며 마우스 위치도 복원한다. 첫 OLE 포인터 복원 시도는 Windows 오류로 실패했으므로 그 시도의 원래 클립보드 내용 보존을 주장하지 않는다. 이후 WinRT snapshot 방식의 복원과 fixture 종료는 통과했다. 실제 사용자 계정 파일은 읽거나 변경하지 않았다.

Core 272 / App 338개 검증이 통과했다. 새 입력은 기존 업로드 계약을 사용하며 운영 DB·Storage 정책·Mac 소스 변경은 없다. 외부 File Explorer·브라우저의 모든 드래그 형식과 실제 서버 UI 송수신, 기기 QA 전체의 완료를 뜻하지 않는다. Windows 설치 후보 버전은 0.4.9.0이다.

API 기준: [Microsoft 드래그와 드롭](https://learn.microsoft.com/en-us/windows/apps/design/input/drag-and-drop), [클립보드](https://learn.microsoft.com/en-us/windows/apps/develop/communication/copy-and-paste), [PreviewKeyDown](https://learn.microsoft.com/en-us/windows/windows-app-sdk/api/winrt/microsoft.ui.xaml.uielement.previewkeydown?view=windows-app-sdk-2.0).
