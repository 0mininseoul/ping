# Ping — 실시간 2초 영상 메시지 macOS 앱 기획서 (v2.2)

## 프로젝트 개요

**Ping**은 macOS 13 Ventura 이상에서 동작하는 2초 영상 메시지 메뉴바 앱이다. Option+P로 원형 카메라 거울을 띄우고, Enter로 정확히 2초 녹화한 뒤 Supabase를 통해 파트너에게 전송한다. 수신자는 로컬 알림을 클릭하면 발신자가 보낸 위치에 2초 원형 재생창이 뜬다.

> 현재 구현(v0.3.20)은 v0.2.1 amendment를 반영해 녹화 길이를 3초로 사용한다. Option+P는 얼굴만, Option+L은 화면+얼굴 캡쳐, Option+O는 내 룸/히스토리 창 진입점이다.
> v0.3.20은 히스토리 타임스탬프 swipe reveal 즉시 복귀와 고정 timestamp lane, delta 0 release/cancel 처리, 수직 momentum pass-through 및 reset storm 방지, 입력 필드 위 리스트 하단 여백, 더 큰 인라인 영상 player frame과 overshoot 없는 확대 모션, AppKit view layout 이후 0초부터 시작하는 인라인 영상 재생, SwiftUI context를 캡처하지 않는 인라인 영상 layer layout으로 영상 클릭 후 CPU 100% 레이아웃 루프 방지, 3명 이상 룸에서 상대 영상 메시지 sender label 표시, 다크모드 날짜 header 배경 바 제거, 룸 매니저 우측 툴바 고정, 컴팩트 사이드바와 16자 룸 이름 제한, 로컬 sent/received 아카이브 기반 히스토리 썸네일/인라인 재생 fallback을 포함한다.

### 초기 검증 환경

- 박영민 Apple Silicon Mac
- 테스트 Apple Silicon Mac

### 목표

- 두 사람 간 즉석 영상 메시지 UX를 검증한다.
- DMG 기반 배포와 Sparkle 자동 업데이트 흐름을 갖춘다.
- 룸 생성, 검색, 초대, 초대 링크를 통해 향후 사용자 확장을 지원한다.

### 단일 진실 출처

- Backend schema/RLS/RPC/Storage 정책: `supabase/migrations/*.sql`
- Supabase runtime wrapper: `Ping/Backend/SupabaseClient.swift`
- Supabase bundle config 예시: `Resources/Supabase.example.plist`
- Xcode project source: `project.yml`
- App version: `project.yml`의 `MARKETING_VERSION`

## 시스템 요구사항

| 항목 | 요구사항 |
|---|---|
| 운영체제 | macOS 13 Ventura 이상 |
| 아키텍처 | Apple Silicon Mac 권장, Intel Mac은 v0.1.4에서 실기기 검증 전 |
| 카메라 | 내장 FaceTime 카메라 또는 외장 USB 카메라 |
| 마이크 | 내장 또는 외장 |
| 네트워크 | Supabase Auth, Postgres RPC, Storage 접근 가능 |

macOS 26 이상에서는 `.pingGlassEffect()` wrapper가 SwiftUI 네이티브 `.glassEffect()`를 사용하고, macOS 13-25에서는 `PingDesign.Surface` 기반 fallback surface를 사용한다. 앱 코드는 `.pingGlassEffect()` wrapper만 호출한다.

## 핵심 기능

### 시스템 통합

- 글로벌 단축키: 기본 `Option + P`, `KeyboardShortcuts` 패키지 사용.
- 메뉴바 상주 앱: `NSStatusItem`, Dock 아이콘 숨김, `LSUIElement = true`.
- 로그인 시 자동 시작: `SMAppService.mainApp` 기반 Settings 토글.
- 자동 업데이트: Sparkle 2, `SUFeedURL = https://ping0min.vercel.app/appcast.xml`, scheduled update는 gentle reminder 알림을 함께 표시.

### 권한

| 권한 | 필수도 | 거부 시 동작 |
|---|---|---|
| 카메라 | 필수 | 송신 불가, Settings 안내 |
| 마이크 | 필수 | 음성 없는 영상 fallback 검토 |
| 알림 | 필수 | 수신 polling은 가능하나 배너 미표시 |
| 자동 시작 | 옵션 | 수동 실행 |

### 룸과 파트너

- 모든 메시지는 룸 단위로 전송된다.
- 현재 서버 제한은 사용자당 최대 8개 룸, 룸당 최대 4명이다.
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

### 수신 재생

- Supabase polling으로 새 메시지를 감지하면 로컬 알림을 띄운다.
- 알림 클릭 또는 액션 선택 시 Storage에서 영상을 다운로드한다.
- 발신자의 `x_ratio`, `y_ratio`를 수신자 메인 스크린 좌표로 변환하고 safe area로 clamp한다.
- 200px 원형 playback window에서 정확히 2초 재생한 뒤 닫는다.
- 재생 후 `ping_mark_message_seen(message_uuid)`를 호출한다.

### Settings

| 탭 | 내용 |
|---|---|
| 일반 | 로그인 시 자동 시작, 닉네임 |
| 단축키 | 글로벌 단축키 재바인딩 |
| 룸 | 룸 목록, 이름 변경, 나가기, 룸 찾기 |
| 저장 | 로컬 저장 경로, Finder 열기, 자동 저장 토글 |
| 정보 | 버전, 업데이트, 링크 |

## 촬영 시스템

- `AVCaptureSession.Preset.hd1920x1080`
- 30fps, H.264, AAC, MP4
- `AVCaptureMovieFileOutput.maxRecordedDuration`으로 2초 제한
- 녹화 파일은 임시 경로로 만든 뒤 설정에 따라 `~/Documents/Ping/sent/`로 이동한다.
- 수신 파일은 `~/Documents/Ping/received/`에 저장한다.

## Supabase 백엔드

### 런타임 설정

앱 번들에는 `Resources/Supabase.plist`가 필요하다. 이 파일은 git에 커밋하지 않는다.

```xml
<key>SUPABASE_URL</key>
<string>https://YOUR_PROJECT_REF.supabase.co</string>
<key>SUPABASE_ANON_KEY</key>
<string>YOUR_SUPABASE_ANON_KEY</string>
<key>PING_INVITE_BASE_URL</key>
<string>https://ping0min.vercel.app</string>
```

원격 프로젝트 적용:

```bash
npx supabase link --project-ref YOUR_PROJECT_REF
npx supabase db push
```

Supabase Dashboard에서 Anonymous sign-ins가 켜져 있어야 한다.

### 인증

- Supabase Anonymous Auth만 사용한다.
- `SupabaseClient`는 access/refresh token을 sandboxed Application Support의 `SupabaseSession.json`에 저장하고, legacy `UserDefaults` 세션만 fallback으로 읽는다.
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
2. `VideoRecorder`가 2초 MP4를 만든다.
3. `StorageService.uploadVideo`가 `ping-videos/<senderUid>/<videoId>.mp4`로 업로드한다.
4. `MessageService.send`가 receiver별 `ping_create_message` RPC를 호출한다.
5. 단일 룸 송신이면 `ping_update_last_used_room`으로 기본 룸을 갱신한다.
6. 성공 시 윈도우는 0.3초 후 닫히며 toast를 띄우지 않는다.

### 수신 플로우

1. 앱 시작 후 `ping_incoming_messages()`를 2초 간격으로 polling한다.
2. 세션 내 `yieldedIds`와 앱 전역 `notifiedMessageIds`로 중복 알림을 막는다.
3. 알림 클릭 시 `ping_get_message(message_uuid)`로 최신 메타데이터를 읽는다.
4. Storage 객체를 다운로드하고 원형 playback window를 연다.
5. 재생 완료 후 `ping_mark_message_seen(message_uuid)`를 호출한다.

### 데이터 정리

- 서버 예약 작업은 사용하지 않는다.
- 앱 실행 중 `ping_cleanup_expired_data()`를 best-effort로 호출한다.
- 만료 기준은 messages와 영상 24시간, invitations와 invite links 7일이다.

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

## 개발 환경

필수 도구:

```bash
xcode-select -p
xcodebuild -version
swift --version
brew install xcodegen create-dmg
npx supabase --version
```

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
| 녹화 → 전송 | 업로드와 message 생성 후 윈도우 닫힘 |
| 수신 알림 | 중복 없이 로컬 알림 표시 |
| 알림 클릭 → 재생 | Storage 다운로드 후 2초 재생 |
| 전체 발송 | 영상 하나를 공유하고 receiver별 메시지 생성 |
| 자동 업데이트 | appcast와 EdDSA 서명 검증 |

## 보안 및 프라이버시

- 전송은 Supabase HTTPS를 사용한다.
- Storage bucket은 private이다.
- RLS와 security definer RPC로 sender, receiver, room member 경계를 제한한다.
- 서버 영상과 메시지는 만료 후 best-effort cleanup 대상이다.
- 로컬 영상은 사용자 디바이스에만 저장된다.
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
