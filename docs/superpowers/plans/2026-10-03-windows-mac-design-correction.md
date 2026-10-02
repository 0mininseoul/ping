# Windows 화면을 현재 Mac 제품 구조로 교정

사용자는 기존 Windows 데모 디자인을 버리고 최신 Mac UI/UX를 기준으로 만들 것을 처음부터 요청했다. 현재 구현은 기능·설치 검증에 치우쳤으며 특히 RoomManagerWindow의 영어 폼 화면과 메인 창의 과한 카드/브랜딩이 그 요구를 충족하지 못했다. 기존 승인 범위에서 화면을 교정한다.

## 직접 참고하는 현재 원본

- `Ping/UI/Setup/RoomManagerWindow.swift`: 작은 룸 사이드바, 룸별 대화, 생성·검색 별도 진입점.
- `Ping/UI/Setup/RoomDetailView.swift`: 16pt/10pt 헤더 여백, 얇은 구분선, 작은 룸 제목/멤버 수.
- `Ping/UI/History/ChatMessageRowView.swift`: 내 메시지 파란색/흰 글자, 상대 메시지 회색, 14pt 말풍선, 타이트한 간격.
- `Ping/UI/History/ChatComposerView.swift`: 36pt 입력, 30pt 원형 첨부/전송, 12pt/8pt 여백.
- `Ping/UI/Glass/PingDesign.swift`: adaptive accent와 dark surface. Windows 시스템 글꼴·창 제어를 사용한다.

## 이번 작업

1. 메인 대화를 compact split layout으로 교정한다. 큰 로고/슬로건 및 대화 바깥 카드를 제거하고 헤더·말풍선·입력을 원본 기준으로 수정한다. 기존 바인딩, 전송/답장/반응/이미지/재생 경로를 보존한다.
2. 룸 관리 창의 모든 관리 폼을 한 화면에 펼치던 구성을 탭으로 분리하고 한국어로 정리한다. 사용자는 닉네임으로 사람을 검색하며 raw UID를 입력하지 않는다. 기존 룸/검색/초대 동작은 실제 서비스에 연결한다.
3. 정상 Release 빌드와 기존 실제 WinUI 동작 검사를 실행하고 DISPLAY3에서 변경 화면을 렌더링해 확인한다. 설정/거울/리뷰 전체 디자인 일치와 실제 Mac 실행 화면 비교는 후속 항목이며 이번 수정으로 전체 디자인 완료라고 말하지 않는다.

Mac 실행 화면을 이 Windows 환경에서 캡처하지 못했으므로 현재 단계는 원본 코드 기반 교정이다. 과거 테스트 이미지나 소스 분석을 실제 Mac 화면의 시각적 감사로 주장하지 않는다. 사용자 계정/기존 설치 앱을 강제 종료하거나 바꾸지 않고 합성 서비스 진단 빌드로 화면을 확인한다.

Commit: `fix(windows-ui): match Mac room and conversation structure`.

구현/로컬 확인: App309, WinUI175(DISPLAY3), 정상 x64 Release 경고/오류0. 원본의 메시지 최대 폭280, 11/6 여백, 얼굴60/화면90 썸네일까지 교정했다. Windows0.4.2.0으로 구분하며 서명 EXE 생성은 후속 배포 작업으로 이어간다. 설정/온보딩/거울/리뷰의 전체 시각적 parity 및 실제 Mac 이미지 대조는 완료로 표시하지 않는다.
