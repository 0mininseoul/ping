# Ping — 실시간 3초 영상 메시지 macOS/Windows 앱 기획서 (v2.8)

## 프로젝트 개요

**Ping**은 macOS 13 Ventura 이상에서 동작하는 3초 영상 메시지 메뉴바 앱이며, Windows 11 24H2 이상용 네이티브 클라이언트를 같은 Supabase 룸/메시지 계약으로 제공한다. macOS는 Option+P/Option+L, Windows는 Alt+P/Alt+L로 거울을 띄우고, Enter로 정확히 3초 녹화한 뒤 review 재생에서 Enter로 Supabase를 통해 파트너에게 전송한다. 수신자는 로컬 알림을 클릭하면 발신자가 보낸 위치 또는 해당 플랫폼의 playback surface에서 3초 재생창을 본다.

> 현재 구현(v0.3.41)은 v0.2.1 amendment를 반영해 녹화 길이를 3초로 사용한다. Option+P는 얼굴만, Option+L은 화면+얼굴 캡쳐, Option+O는 내 룸/히스토리 창 진입점이다. Windows 클라이언트는 Alt+P, Alt+L, Alt+O와 Alt+Shift+L quick screen+face send를 대응 단축키로 사용한다.
> macOS 앱은 Dock에 절대 표시되지 않도록 번들 `LSUIElement` agent 분류를 사용하고, 런타임에서도 accessory activation을 재적용한다. v0.3.39의 runtime-only Dock hiding은 Finder/Spotlight 실행 순간 Dock tile이 생길 수 있어 현재 정책이 아니다. v0.3.28은 Sparkle scheduled update 알림을 버전별 1회로 제한하고, 더 최신 버전이 나오면 기존 업데이트 알림을 최신 버전 알림 하나로 교체한다. v0.3.27은 룸 알림 정리, 최신 메시지 스크롤, Enter 전송/Shift+Enter 줄바꿈, 채팅 사진 첨부를 포함한다. v0.3.26은 화면+얼굴 메시지 확대 재생 크기를 키우고, 확대 시 해당 영상 하단이 보이도록 자동 스크롤한다. v0.3.25는 내 룸 화면에서 화면+얼굴 메시지를 확대할 때 영상이 사라지지 않도록 확장 overlay를 룸 매니저 루트에서 렌더링한다. v0.3.24는 화면+얼굴 프리뷰와 실제 저장 영상의 얼굴 PIP 비율을 같은 레이아웃 계약으로 통일하고, 히스토리 확대 재생 시 사이드바 폭을 유지한 채 영상이 사이드바 위로 확장되어 전체 화면이 잘리지 않게 한다. 발신자 제어형 로컬 저장 권한 설정도 포함한다. v0.3.23은 온보딩 권한 화면에서 macOS 권한 재확인이 지연돼도 이후 3~7단계를 계속 볼 수 있게 하고, 릴리즈 앱의 ad-hoc designated requirement를 bundle id 기준으로 고정해 업데이트 후 TCC 권한 판정이 빌드 해시 변화에 흔들리지 않도록 한다. v0.3.22의 온보딩 header/progress 고정, 미니멀 권한 체크리스트, 알림 프롬프트 시작 시점 소모 방지도 포함한다. 화면 녹화 권한의 passive check는 시스템 프롬프트를 띄우지 않는 CoreGraphics preflight만 사용하며, macOS가 요구하는 앱 재시작 안내를 표시한다. 기존 v0.3.21의 히스토리 타임스탬프 swipe reveal, 인라인 영상 재생 안정화, 그룹 룸 sender label, 다크모드 날짜 header 정리, 컴팩트 사이드바와 로컬 아카이브 fallback도 포함한다.

### 초기 검증 환경

- 박영민 Apple Silicon Mac
- 테스트 Apple Silicon Mac

### 목표

- 두 사람 간 즉석 영상 메시지 UX를 검증한다.
- DMG 기반 배포와 Sparkle 자동 업데이트 흐름을 갖춘다.
- 룸 생성, 검색, 초대, 초대 링크를 통해 향후 사용자 확장을 지원한다.
- Windows 사용자가 Mac 사용자와 같은 룸에서 `face_only`와 `screen_face` 메시지를 주고받도록 한다.

### 단일 진실 출처

- Backend schema/RLS/RPC/Storage 정책: `supabase/migrations/*.sql`
- Supabase runtime wrapper: `Ping/Backend/SupabaseClient.swift`
- Windows runtime wrapper: `windows/src/Ping.Windows.Core/Backend/SupabaseClient.cs`
- Supabase bundle config 예시: `Resources/Supabase.example.plist`
- Xcode project source: `project.yml`
- Windows solution source: `windows/PingWindows.sln`
- macOS App version: `project.yml`의 `MARKETING_VERSION`
- Windows package version: `windows/src/Ping.Windows.App/Package.appxmanifest`의 `Identity.Version`. macOS Sparkle 릴리즈와 Windows MSIX 릴리즈는 서로 다른 배포 채널이므로 같은 버전일 필요가 없다.

## 시스템 요구사항

| 항목 | 요구사항 |
|---|---|
| 운영체제 | macOS 13 Ventura 이상, Windows packaged client는 Windows 11 24H2 이상 |
| 아키텍처 | Apple Silicon Mac 권장, Windows x64/ARM64 |
| 카메라 | 내장 FaceTime 카메라 또는 외장 USB 카메라 |
| 마이크 | 내장 또는 외장 |
| 네트워크 | Supabase Auth, Postgres RPC, Storage 접근 가능 |

macOS 26 이상에서는 `.pingGlassEffect()` wrapper가 SwiftUI 네이티브 `.glassEffect()`를 사용하고, macOS 13-25에서는 `PingDesign.Surface` 기반 fallback surface를 사용한다. 앱 코드는 `.pingGlassEffect()` wrapper만 호출한다.

## 핵심 기능

### 시스템 통합

- 글로벌 단축키: 기본 `Option + P`, `KeyboardShortcuts` 패키지 사용.
- 메뉴바 상주 앱: `NSStatusItem`, 앱 번들은 `LSUIElement` agent로 분류해 Finder/Spotlight/응용프로그램 실행 중에도 Dock 아이콘을 만들지 않고, 런타임에서 accessory activation을 추가로 재적용한다.
- 로그인 시 자동 시작: `SMAppService.mainApp` 기반 Settings 토글.
- 자동 업데이트: Sparkle 2, `SUFeedURL = https://0minping.vercel.app/appcast.xml`, scheduled update는 gentle reminder 알림을 함께 표시.

### Windows 시스템 통합

- 글로벌 단축키: 기본 `Alt+P`, `Alt+L`, `Alt+Shift+L`, `Alt+O`, Win32 `RegisterHotKey` 사용.
- 트레이 상주 앱: Win32 `Shell_NotifyIcon` 기반 notification area icon.
- 알림: Windows App SDK app notifications. Elevated/admin 실행에서는 알림이 지원되지 않으므로 일반 권한 재실행을 안내한다.
- 히스토리: 열린 룸은 Supabase chat/video RPC를 짧은 주기로 polling해 macOS Realtime 히스토리와 유사하게 채팅, 첨부 이미지, 답장, 반응 변경을 반영하며, 채팅 알림 클릭 시 해당 룸의 알림 대상 채팅 row를 선택한다. 채팅 입력은 Enter 전송, Shift+Enter 줄바꿈을 사용한다.
- 패키징: Windows App SDK packaged full-trust MSIX. 비용 없는 직접 배포는 signed MSIX를 `PingSetup-v0.3.30.exe` 웹 설치파일로 감싸고, 설치 중 `https://0minping.vercel.app/downloads/windows/`에서 PC 아키텍처에 맞는 MSIX를 내려받는 랜딩페이지 다운로드를 기본 UX로 사용한다. sideload zip은 fallback/debug 경로로 유지한다. Windows는 Sparkle을 사용하지 않고 MSIX/App Installer 또는 Store 업데이트 채널을 사용한다.

### 권한

| 권한 | 필수도 | 거부 시 동작 |
|---|---|---|
| 카메라 | 필수 | 송신 불가, Settings 안내 |
| 마이크 | 필수 | 음성 없는 영상 fallback 검토 |
| 알림 | 필수 | 수신 polling은 가능하나 배너 미표시 |
| 자동 시작 | 옵션 | 수동 실행 |

Windows packaged client는 Windows 11 24H2 미만에서는 설치 대상이 아니다. Onboarding은 OS 버전, elevated 실행 여부, Supabase config, camera, microphone, screen capture, notifications, hotkey 충돌, startup availability를 별도 row로 확인한다. 화면 캡처는 Windows Graphics Capture desktop interop을 기본 경로로 사용하고, DRM/protected content, secure desktop, 일부 GPU overlay는 검은 화면 또는 실패로 표시될 수 있다.

### 룸과 파트너

- 모든 메시지는 룸 단위로 전송된다.
- 현재 서버 제한은 사용자당 최대 8개 룸, 룸당 최대 8명이다.
- `rooms.status`는 멤버 수가 제한에 도달하면 `full`, 아니면 `open`이다.
- 앱의 기본 송신 대상은 `profiles.last_used_room_id`와 로컬 `AppState.defaultRoom`으로 결정한다.
- 단일 룸 송신은 그 룸의 본인 제외 멤버에게 메시지를 만든다.
- 전체 발송은 sendable room 전체에 대해 한 영상 객체를 공유하고 receiver별 메시지를 만든다.

### 룸 생성, 검색, 초대

- 룸 만들기: `ping_create_room(room_name, searchable_room_name, owner_nickname)`
- 내 룸 polling: `ping_my_rooms()`
- 열린 룸 검색: `ping_search_open_rooms(search_prefix)`
- 사용자 검색: `ping_search_profiles(search_prefix)`
- 룸 참여: `ping_join_room(room_uuid, nickname_text)`
- 사용자 초대: `ping_invite_user(target_uid, inviter_nickname_text, room_name_text, searchable_room_name)`
- 기존 룸 초대: `ping_send_invitation(to_uid, room_uuid, from_nickname, room_name_text)`
- 초대 수락/거절: `ping_accept_invitation`, `ping_reject_invitation`
- 초대 링크 생성/수락: `ping_create_invite_link`, `ping_accept_invite_link`

## UI 명세

### 송신 거울

- 200px 원형 borderless floating window.
- 메인 스크린에 표시하며 마지막 위치를 저장한다.
- SwiftUI `.pingGlassEffect()` 기반 compatible glass 스타일.
- `AppDelegate`가 보유한 단일 `CameraManager` 인스턴스를 주입한다.

| 상태 | 시각 표현 |
|---|---|
| 대기 | 글래스 보더, 카메라 프리뷰, 하단 파트너 칩 |
| 녹화 | 빨간 2pt 보더, 우측 상단 `2 / 1` countdown |
| 업로드 | 회전 그라데이션 보더, 하단 `전송 중...` |
| 완료 | 0.3초 fade-out 후 닫힘. 별도 toast 없음 |
| 실패 | 노란 2pt 보더, 인라인 실패 문구. Enter로 재시도 |

### 파트너 선택

- 하단 칩은 현재 타겟을 표시한다.
- 칩 클릭 시 모든 파트너와 `모두에게` 옵션을 보여준다.
- `Tab`: 다음 파트너
- `1`~`9`: N번째 파트너
- `0` 또는 `A`: 전체 발송
- `Enter`: 녹화 시작
- `Esc`: 닫기

### 화면+얼굴 캡처 영역

- Option+L 프리뷰는 매번 1.0× 전체 화면으로 시작한다.
- 프리뷰가 준비되면 `Option+스크롤`, `Option+두 손가락 핀치`, `Option+커서 이동`, `Enter`, `Esc` 사용법을 3초간 상세히 안내한 뒤, 화면을 덜 가리는 한 줄 축약 안내로 자동 전환한다.
- `Option+아래에서 위로 스크롤`하면 화면 캡처 영역을 확대하고, `Option+위에서 아래로 스크롤`하면 축소한다.
- `Option`을 누른 채 트랙패드에서 두 손가락을 펼치면 확대하고, 오므리면 축소한다. 커서가 프리뷰 창 밖에 있어도 동작해야 한다.
- 화면 캡처 영역은 두 입력 모두 1.0×~4.0× 범위로 제한한다.
- `Option`을 누른 채 마우스를 움직이면 포인터가 있는 위치로 캡처 중심 X/Y가 이동하고, `Option`을 놓으면 현재 영역이 고정된다.
- `Option+0`은 전체 화면 1.0×로 초기화한다.
- 프리뷰 창의 위치와 크기, 우측 하단 얼굴 PIP는 유지하고 화면 레이어에만 확대/이동을 적용한다.
- `Enter`를 누르는 순간 캡처 영역을 잠그고, 녹화와 review 중에는 확대/이동 입력을 무시한다.
- 프리뷰와 실제 MP4 녹화는 동일한 크롭 영역을 사용한다.
- 화면 캡처는 현재 Ping 번들 ID와 일치하는 모든 실행 프로세스를 `SCContentFilter` 제외 목록에 넣는다. WindowServer 반영 지연으로 Ping을 찾지 못하면 제한된 횟수로 재시도하고, 끝내 제외하지 못하면 자기 재귀 화면을 송출하지 않고 프리뷰를 중단한다.

### 수신 재생

- Supabase polling으로 새 메시지를 감지하면 로컬 알림을 띄운다.
- 알림 클릭 또는 액션 선택 시 Storage에서 영상을 다운로드한다.
- 발신자의 `x_ratio`, `y_ratio`를 수신자 메인 스크린 좌표로 변환하고 safe area로 clamp한다.
- Face-only는 200px 원형 playback window, screen+face는 저장된 `aspect_ratio` 기반 compact playback window에서 발신자 위치에 맞춰 재생한다.
- 첫 재생이 끝나면 `ping_mark_message_seen(message_uuid)`를 1회 호출하고, 창은 잠시 유지한다. `Enter`로 다시 재생하거나 `Esc`로 닫을 수 있으며, 추가 입력이 없으면 약 10초 뒤 fade-out한다.

### Settings

| 탭 | 내용 |
|---|---|
| 일반 | 로그인 시 자동 시작, 닉네임 |
| 단축키 | 글로벌 단축키 재바인딩 |
| 룸 | 룸 목록, 이름 변경, 나가기, 룸 찾기, 닉네임 기반 사용자 검색/초대, 초대 링크 |
| 저장 | 로컬 저장 경로, Finder/Explorer 열기, 보낸 영상 저장, 받은 영상 자동 저장, 상대 저장 허용, 30일 뒤 자동 삭제 토글 |
| 정보 | 버전, 업데이트, 링크 |

## 촬영 시스템

- `AVCaptureSession.Preset.hd1920x1080`
- 30fps, H.264, AAC, MP4
- `AVCaptureMovieFileOutput.maxRecordedDuration`으로 3초 제한
- screen+face는 Option+L 프리뷰에서 잠긴 `ScreenCaptureViewport` 크롭을 화면 프레임에 적용한 뒤 얼굴 PIP를 합성한다.
- 녹화 파일은 임시 경로로 만든 뒤 설정에 따라 `~/Documents/Ping/sent/`로 이동한다.
- 수신 파일은 수신자의 자동 저장 설정이 켜져 있고 발신자가 로컬 저장을 허용한 메시지일 때만 `~/Documents/Ping/received/`에 저장한다.

## Supabase 백엔드

### 런타임 설정

앱 번들에는 `Resources/Supabase.plist`가 필요하다. 이 파일은 git에 커밋하지 않는다.

```xml
<key>SUPABASE_URL</key>
<string>https://YOUR_PROJECT_REF.supabase.co</string>
<key>SUPABASE_ANON_KEY</key>
<string>YOUR_SUPABASE_ANON_KEY</string>
<key>PING_INVITE_BASE_URL</key>
<string>https://0minping.vercel.app</string>
```

원격 프로젝트 적용:

```bash
./scripts/supabase-ping.sh link --project-ref qxjtprxvjmaxlbtljcjw
./scripts/supabase-ping.sh db push
```

Supabase Dashboard에서 Anonymous sign-ins가 켜져 있어야 한다.

Windows 클라이언트는 macOS plist를 사용하지 않고 다음 JSON 파일을 읽는다.

Windows도 Settings > General의 닉네임 저장 시 `ping_upsert_profile`을 호출하고, 이후 룸 생성/초대/영상 메시지의 발신자 표시에는 OS 계정명이 아니라 저장된 Supabase 프로필 닉네임을 사용한다.

```text
%LOCALAPPDATA%\Ping\Supabase.json
```

```json
{
  "url": "https://YOUR_PROJECT_REF.supabase.co",
  "anonKey": "YOUR_SUPABASE_ANON_KEY"
}
```

### 인증

- Supabase Anonymous Auth만 사용한다.
- `SupabaseClient`는 access/refresh token을 sandboxed Application Support의 `SupabaseSession.json`에 저장하고, legacy `UserDefaults` 세션만 fallback으로 읽는다.
- Sparkle 업데이트나 `/Applications/Ping.app` 교체는 앱 번들만 바꾸며, bundle id `com.youngminpark.ping.Ping`과 위 세션 파일 경로를 유지해야 기존 익명 계정과 룸이 그대로 연결된다.
- ad-hoc으로 자주 교체 배포하는 현재 배포 방식에서는 macOS Keychain ACL 승인 팝업이 재발할 수 있으므로 앱 런타임 세션 저장/갱신 경로에서 Keychain을 사용하지 않는다. Sparkle appcast 서명용 개인키 Keychain 사용과는 별개다.
- 기존 세션 refresh가 실패하면 보존된 사용자 데이터를 잃지 않도록 새 익명 사용자로 자동 전환하지 않고 `supabaseSessionExpired`를 띄운다.

### 데이터 모델

주요 테이블:

- `profiles`: 사용자 닉네임, 검색용 닉네임, 마지막 룸.
- `rooms`: 룸 이름, 검색용 이름, owner, status.
- `room_members`: 룸 멤버, 닉네임, role.
- `invitations`: 사용자 간 초대.
- `invite_links`: 설치/초대 링크 토큰.
- `messages`: receiver별 메시지 메타데이터, video path, 위치 ratio, 상태.

`messages`의 위치 ratio는 `0...1` 범위 check constraint를 갖는다. 송신 좌표는 서버 호출 전에 유효 범위로 보장되어야 한다.

### Storage

- Bucket: `ping-videos`
- Public: false
- MIME: `video/mp4`
- 파일 크기 제한: 50MB
- 객체 경로: `<senderUid>/<videoId>.mp4`
- 업로드는 객체 첫 folder가 `auth.uid()`와 같을 때만 허용한다.
- 다운로드는 sender 또는 해당 message receiver에게만 허용한다.

### 송신 플로우

1. Option+P → 거울 등장 → 파트너 선택 → Enter.
2. `VideoRecorder`가 3초 MP4를 만든다.
3. `StorageService.uploadVideo`가 `ping-videos/<senderUid>/<videoId>.mp4`로 업로드한다.
4. `MessageService.send`가 receiver별 `ping_create_message` RPC를 호출한다.
5. 단일 룸 송신이면 `ping_update_last_used_room`으로 기본 룸을 갱신한다.
6. 성공 시 윈도우는 0.3초 후 닫히며 toast를 띄우지 않는다.

### 수신 플로우

1. 앱 시작 후 `ping_incoming_messages()`를 10초 간격으로 polling한다.
2. 세션 내 `yieldedIds`와 앱 전역 `notifiedMessageIds`로 중복 알림을 막는다.
3. 알림 클릭 시 `ping_get_message(message_uuid)`로 최신 메타데이터를 읽는다.
4. Storage 객체를 다운로드하고 원형 playback window를 연다.
5. 재생 완료 후 `ping_mark_message_seen(message_uuid)`를 호출한다.

### 데이터 정리

- 서버 예약 작업은 사용하지 않는다.
- 앱 실행 중 `ping_cleanup_expired_data()`를 best-effort로 호출한다.
- 만료 기준은 messages와 영상 30일, invitations와 invite links 7일이다.

## 로컬 저장

기본 경로:

```text
~/Documents/Ping/
├── sent/
└── received/
```

파일명 예:

```text
sent/2026-05-17_14-30-25_to_partner.mp4
sent/2026-05-17_14-30-25_to_all.mp4
received/2026-05-17_14-32-18_from_박영민.mp4
```

저장 정책:

- `보낸 영상 저장`은 본인 기기에 남길 송신 사본만 제어한다.
- `상대가 내 영상 저장 가능`은 이후 전송되는 메시지의 `allows_local_save` 값으로 저장된다. 기본값은 꺼짐이다.
- `받은 영상 자동 저장`은 상대가 `allows_local_save`를 허용한 영상에만 적용된다.
- `30일 뒤 자동 삭제`를 켜면 앱 실행 또는 설정 변경 시 로컬 `sent/`, `received/` 폴더의 30일 지난 MP4 사본을 정리한다.
- Windows Settings > Storage는 같은 archive root를 표시하고 Explorer로 열 수 있어야 한다.
- 룸 히스토리 재생은 서버 영상과 임시 캐시를 사용할 수 있지만, 명시적 로컬 저장 액션은 발신자가 허용한 받은 영상에만 표시된다.

## 개발 환경

필수 도구:

```bash
xcode-select -p
xcodebuild -version
swift --version
brew install xcodegen create-dmg
npx supabase --version
```

Windows 필수 도구:

```powershell
dotnet --version
dotnet --list-sdks
msbuild -version
```

Windows 빌드는 .NET 10, Visual Studio .NET desktop, Desktop development with C++, Windows App SDK tooling, Windows SDK `10.0.26100.0` 이상을 요구한다.

빌드:

```bash
xcodegen generate
xcodebuild -project Ping.xcodeproj -scheme Ping -configuration Debug -destination "platform=macOS" build
```

테스트:

```bash
xcodebuild -project Ping.xcodeproj -scheme Ping -destination "platform=macOS" test
```

Release/DMG:

```bash
./scripts/build-release.sh
```

Windows Release/MSIX:

```powershell
.\windows\scripts\build-release.ps1
.\windows\scripts\smoke-release.ps1
```

## 주요 파일 구조

```text
ping/
├── AGENTS.md
├── PING_PROJECT_SPECIFICATION.md
├── README.md
├── project.yml
├── Ping/
│   ├── AppDelegate.swift
│   ├── Backend/
│   │   ├── SupabaseClient.swift
│   │   ├── RoomService.swift
│   │   ├── InvitationService.swift
│   │   ├── MessageService.swift
│   │   ├── StorageService.swift
│   │   └── CleanupService.swift
│   ├── Capture/
│   ├── Core/
│   ├── Hotkey/
│   ├── Notifications/
│   ├── UI/
│   └── Updater/
├── PingTests/
├── Resources/
│   └── Supabase.example.plist
├── scripts/
├── supabase/
│   └── migrations/
├── windows/
│   ├── PingWindows.sln
│   ├── scripts/
│   ├── src/
│   └── tests/
└── web/
```

## 디자인 원칙

- Liquid Glass는 `.pingGlassEffect()` wrapper를 통해 적용한다.
- macOS 26 이상에서는 SwiftUI 네이티브 `.glassEffect()`를 사용하고, macOS 13-25에서는 `PingDesign.Surface` 기반 fallback surface를 사용한다.
- 거울과 재생창은 원형, 카드와 패널은 16pt radius.
- 시스템 폰트만 사용한다.
- 송신 완료 시 별도 toast나 성공 문구를 띄우지 않는다.

상태별 보더:

| 상태 | 색 |
|---|---|
| 대기 | `Color.white.opacity(0.30)`, 1pt |
| 녹화 | `#FF3B30`, 2pt |
| 실패 | `#FFCC00`, 2pt |
| 전체 발송 | 회전 rainbow gradient, 2pt |

## QA 체크리스트

| 시나리오 | 통과 기준 |
|---|---|
| 첫 실행 | Supabase config 누락 시 명확한 안내 |
| Anonymous Auth | 세션이 재실행 후에도 유지됨 |
| 룸 생성/검색 | prefix 검색과 룸 참여가 동작 |
| 초대/초대 링크 | 수락 후 양쪽 룸 목록 갱신 |
| Option+P | 다른 앱 포커스에서도 거울 표시 |
| Option+L 확대/이동 | 프리뷰 창은 고정된 채 화면 영역만 1.0×~4.0×로 변경되고, Enter 후 녹화와 일치 |
| Option+L 자기 제외 | 프리뷰 창이 캡처 영상 안에 다시 나타나지 않고, 제외 필터를 구성할 수 없으면 오류를 표시 |
| 녹화 → 전송 | 업로드와 message 생성 후 윈도우 닫힘 |
| 수신 알림 | 중복 없이 로컬 알림 표시 |
| 알림 클릭 → 재생 | Storage 다운로드 후 3초 재생 |
| 전체 발송 | 영상 하나를 공유하고 receiver별 메시지 생성 |
| 자동 업데이트 | appcast와 EdDSA 서명 검증 |
| Windows Alt+Shift+L | 기본 룸에 picker 없이 3초 screen+face 전송 |
| Windows → Mac | Mac 알림/재생/seen 처리 |
| Mac → Windows | Windows 알림/재생/seen 처리 |

## 보안 및 프라이버시

- 전송은 Supabase HTTPS를 사용한다.
- Storage bucket은 private이다.
- RLS와 security definer RPC로 sender, receiver, room member 경계를 제한한다.
- 서버 영상과 메시지는 만료 후 best-effort cleanup 대상이다.
- 로컬 영상은 사용자 디바이스에만 저장된다. 받은 영상의 영구 저장은 발신자가 허용한 메시지에만 앱 UX에서 제공한다.
- 검색은 닉네임과 룸 이름 prefix만 사용한다.

## 향후 로드맵

| 항목 | 내용 |
|---|---|
| 정식 코드 서명 + notarization | Developer ID 배포 품질 개선 |
| 다중 모니터 정밀 처리 | 커서 또는 활성 디스플레이 기준 위치 |
| 파트너별 거울 위치 | 룸마다 기본 위치 기억 |
| 영상 품질 옵션 | 720p/1080p, 비트레이트 |
| 보관 정책 UI | 서버/로컬 보관 기간 설정 |

---

- **문서 버전**: 2.2
- **작성일**: 2026-05-17
- **최종 수정일**: 2026-05-19
- **상태**: Supabase 기반 MVP 구현 기준
