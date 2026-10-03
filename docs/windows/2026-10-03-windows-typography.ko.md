# Windows 글꼴과 UI 세부 요소 개선

사용자 요청: 한글 폰트가 깨진 듯한 인상을 개선하고 Pretendard 또는 나눔체를 포함해 글꼴과 UI 디테일을 함께 조정한다. 기존 AGENTS.md의 시스템 폰트 전용 원칙보다 이 Windows용 요청을 우선한다. macOS 글꼴과 API는 변경하지 않는다.

## 적용 기준

- 공식 Pretendard Variable 1.3.9 원본을 앱 패키지에 포함한다. 시스템 글꼴 설치나 실행 중 다운로드 없이 작동한다. 저작권 및 SIL OFL 1.1 전문을 함께 배포한다.
- 기본 본문 14 DIP / 줄 높이 21, 보조 정보 12 DIP / 줄 높이 18. 제목은 SemiBold로 구분한다. 고정 자간이나 가짜 굵기 보정은 추가하지 않는다.
- 대화 본문, 룸 목록, 검색 결과, 멤버, 설정과 첫 실행에 같은 글꼴을 적용한다. Windows 아이콘 폰트와 이모지 fallback은 유지한다.
- 메시지 입력창 내부 여백을 가로 12 / 세로 8로 맞추고, 초대 수락·거절 버튼의 작은 텍스트와 여백을 조정한다. 대화창의 작은 크기와 기존 기능은 유지한다.

## 검증

실제 WinUI 진단 실행에서 패키지 글꼴이 입력창과 사이드바에 적용되는지, 아이콘 폰트가 보존되는지, 실제 글리프 폭이 시스템 fallback과 구분되는지 검사한다. 라이트·다크, 최소 창 크기, 검색, 설정, 첫 실행 등 기존 native UI 흐름도 함께 검증한다. 화면 렌더는 앱 자체의 RenderTargetBitmap으로 기록한다.

공식 원본: https://github.com/orioncactus/pretendard/tree/v1.3.9

Microsoft 글꼴 기준: https://learn.microsoft.com/en-us/windows/apps/design/signature-experiences/typography

빌드와 설치 결과는 해당 버전 후보 문서에 기록한다. UI 진단 화면은 소유한 fixture 데이터이며, 실제 Mac 화면 비교나 기기 간 전송 완료를 뜻하지 않는다.
