# Windows 작업표시줄 아이콘 수정

사용자가 보낸 작업표시줄 화면의 청록색 사각형은 손상된 그림처럼 보였지만, 소스의 `Square44x44Logo.png` 자체가 청록색 단색 임시 이미지였다. `Square150x150Logo.png`와 `StoreLogo.png`도 같은 상태였다. 창용 ICO 지정만으로는 이 패키지 리소스가 교체되지 않는다.

## 변경

- macOS `Ping/Assets.xcassets/AppIcon.appiconset/app-icon-1024.png`의 기존 투명 아이콘을 재사용한다. macOS 소스와 앱 내부 헤더 디자인은 수정하지 않는다.
- `windows/scripts/generate-shell-icons.ps1`로 Windows 패키지용 PNG와 다중 크기 ICO를 생성한다. 이미지 디자인 변경 없이 기존 그림을 Windows 파일 형식/크기로 변환한다.
- 패키지 manifest를 새 리소스 이름 `PingAppList`, `PingTile`, `PingStoreLogo`에 연결하고 배율 100/125/150/200/400 리소스를 제공한다.
- 작업표시줄용 targetsize 16/20/24/30/32/36/40/48/60/64/72/80/96/256과 unplated/lightunplated 변형을 제공한다.
- 실행 파일·트레이·설치 파일이 사용하는 `Ping.ico`/`app.ico`도 같은 원본으로 생성한다.
- `PingAppearance.Register`가 모든 등록된 창에 아이콘을 지정하여 설정/룸/온보딩 창도 기본 아이콘을 쓰지 않게 한다.
- Windows 버전을 0.4.17.0으로 올린다. 기존 설치물은 자동으로 수정되지 않으며 새 패키지 설치가 필요하다.

자동 테스트·검증 빌드·앱 실행·수정 후 화면 확인·아이콘 캐시 초기화는 하지 않았다. 아이콘 리소스 생성은 구현에 필요한 산출물 작성이며 UI 검증 결과가 아니다. 이전에 고정한 바로가기의 아이콘 캐시 갱신 여부도 미확인이다.

참고: [Microsoft Windows 아이콘 리소스 규격](https://learn.microsoft.com/en-us/windows/apps/design/iconography/app-icon-construction), [AppWindow.SetIcon](https://learn.microsoft.com/en-us/windows/windows-app-sdk/api/winrt/microsoft.ui.windowing.appwindow.seticon).
