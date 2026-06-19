# Ping

3초 영상 메시지 앱. macOS 13 Ventura 이상에서는 메뉴바 앱으로 동작하고, Windows 클라이언트는 Windows 11 24H2 이상에서 같은 Supabase 룸과 메시지 계약을 공유한다.

## Supabase 설정

이 앱은 Supabase Anonymous Auth, Postgres RPC, 비공개 Storage 버킷 `ping-videos`를 사용한다. Supabase 프로젝트의 Project URL과 anon public key를 `Resources/Supabase.plist`에 넣는다. 이 파일은 git에 커밋되지 않는다.

```bash
cp Resources/Supabase.example.plist Resources/Supabase.plist
```

`Resources/Supabase.plist`:

```xml
<key>SUPABASE_URL</key>
<string>https://YOUR_PROJECT_REF.supabase.co</string>
<key>SUPABASE_ANON_KEY</key>
<string>YOUR_SUPABASE_ANON_KEY</string>
<key>PING_INVITE_BASE_URL</key>
<string>https://0minping.vercel.app</string>
```

스키마는 `supabase/migrations/20260517000100_create_ping_backend.sql`에 있다. 원격 프로젝트에 연결한 뒤 적용한다.

```bash
./scripts/supabase-ping.sh link --project-ref qxjtprxvjmaxlbtljcjw
./scripts/supabase-ping.sh db push
```

Supabase Dashboard의 Authentication 설정에서 Anonymous sign-ins가 켜져 있어야 한다.

## 설치

### macOS

1. `Ping-v0.3.50.dmg`를 더블클릭해 마운트한다.
2. `Ping.app`을 Applications 폴더로 드래그한다.
3. 더블클릭해 실행한다. Developer ID 서명 + Apple 공증(notarized) 빌드라 Gatekeeper 경고 없이 바로 열린다.
4. 카메라, 마이크, 알림 권한을 허용한다.
5. 닉네임을 입력한 뒤 룸을 만들거나 상대를 검색해 초대한다.

### Windows

Windows 앱은 `windows/` 아래 별도 네이티브 클라이언트다.

1. 랜딩페이지에서 `PingSetup-v0.3.46.exe`를 내려받아 실행한다.
2. Windows SmartScreen 경고가 보이면 `추가 정보` → `실행`을 선택한다. 무료 자체서명 배포라 정상적인 경고다.
3. UAC 관리자 권한을 승인한다.
4. 설치 프로그램이 공개 인증서 `Ping-Windows-Sideload.cer`를 Windows `Trusted People` 저장소에 등록한 뒤 PC 아키텍처에 맞는 MSIX를 공개 다운로드 서버에서 받아 설치하고 Ping을 실행한다.
5. `%LOCALAPPDATA%\Ping\Supabase.json`에 Supabase URL과 anon key를 저장한다.
6. 온보딩에서 카메라, 마이크, 화면 캡처, 알림, 단축키, 시작프로그램 상태를 확인한다.

`Ping-Windows-v0.3.46-sideload.zip`은 fallback/debug용 배포물이다. 일반 사용자는 `PingSetup-v0.3.46.exe`를 받으면 된다.

자세한 Windows 빌드/설치/QA 절차는 `docs/WINDOWS_APP_SETUP.md`와 `windows/README.md`를 따른다.

## 기존 룸과 익명 계정 보존

Ping은 이메일 로그인 없이 Supabase Anonymous Auth 세션을 로컬에 저장한다. 일반 업데이트나 `Ping.app` 교체는 기존 룸을 유지하지만, 앱 컨테이너의 `Application Support/Ping/SupabaseSession.json`을 삭제하면 새 익명 계정으로 시작한다. 온보딩 QA를 위해 세션을 지울 때는 반드시 이 파일을 먼저 백업하고, QA 뒤 원래 파일을 복구한 다음 Ping을 다시 실행한다.

## 사용

- Option+P: 얼굴만 거울을 띄운다.
- Option+L: 화면+얼굴 거울을 띄운다.
- Option+O: 내 룸/히스토리 창을 연다.
- Windows 기본 대응: Alt+P, Alt+L, Alt+O.
- Windows 빠른 전송: Alt+Shift+L로 기본 룸에 화면+얼굴 메시지를 즉시 3초 녹화/전송한다.
- Windows 단축키 충돌 시 Settings > Hotkeys에서 Ctrl/Alt/Shift/Win 조합과 키를 바꿀 수 있다.
- Enter: 녹화 시작. 리뷰 화면에서 다시 누르면 전송.
- Backspace: 리뷰 화면에서 다시 찍기.
- Esc: 취소 또는 닫기.
- Tab / 1~9: 파트너 전환.
- 0 또는 A: 전체 파트너에게 동시 발송.
- 내 룸 > 초대링크 생성: Mac과 같은 `/invite/<token>` URL을 필드와 클립보드에 복사해 상대에게 보낸다.

## 자동 업데이트

macOS 앱은 Sparkle로 업데이트를 확인한다. 새 버전이 공개되면 알림과 표준 업데이트 다이얼로그가 뜨고, 사용자가 승인하면 바로 다운로드/설치/재시작 흐름으로 진행된다. 같은 버전은 반복 알림하지 않고, 더 최신 버전이 나오면 최신 버전 알림 하나로 교체한다.

0.3.28 초기 빌드(38/39)에서 업데이트 설치 오류가 반복되면 랜딩페이지의 최신 macOS DMG를 한 번 수동으로 내려받아 `Ping.app`을 Applications 폴더에 덮어쓴다. 이 초기 빌드는 Sparkle installer helper 권한/서명이 잘못 들어간 상태라, 현재 실행 중인 앱만으로는 자동 업데이트 설치가 실패할 수 있다. build 40 이상은 Sparkle helper 권한을 보존하고 sandbox mach-lookup 예외를 포함한다.

Windows 앱은 Sparkle을 사용하지 않는다. 비용 없는 배포는 self-signed MSIX를 작은 `PingSetup-v0.3.46.exe` 웹 설치파일로 감싸고, 설치 중 PC 아키텍처에 맞는 MSIX를 `https://0minping.vercel.app/downloads/windows/`에서 받는 방식이다. 최초 설치 시 installer가 Ping 공개 인증서를 등록한다. Microsoft Store, Azure Artifact Signing, OV 코드서명 인증서는 더 매끄러운 신뢰 UX를 제공하지만 비용 또는 외부 계정 검증이 필요하다.

## v0.3.50 macOS 수정

- Spotlight, Finder, 응용프로그램 폴더에서 Ping을 직접 실행해도 Dock에 Ping 아이콘이 뜨지 않도록 macOS 번들을 agent 앱으로 분류했다.

## v0.3.49 macOS/iOS 수정

- YouTube URL 링크 프리뷰가 OG fetch에 실패하거나 이미지 메타데이터를 못 받는 경우에도 안정적인 YouTube 썸네일을 표시하도록 했다.
- macOS 앱과 iOS 공유 PingKit 링크 프리뷰 계약을 함께 보강했다.

## v0.3.48 macOS 수정

- 룸 최대 인원을 4명에서 8명으로 늘렸다.
- 4명 이상 8명 미만인 룸에서도 초대 링크 복사 버튼이 계속 보이도록 했다.

## v0.3.47 macOS 수정

- 재부팅 직후 네트워크가 아직 준비되지 않아 Supabase bootstrap이 한 번 실패하면 내 룸이 비어 보이던 문제를 수정했다.
- 룸 polling 중 일시적인 네트워크 오류가 나도 기존 룸 목록을 빈 목록으로 덮어쓰지 않도록 했다.

## v0.3.46 macOS/Windows/iOS 수정

- 채팅에 URL을 보내면 하이퍼링크로 표시하고, 가능한 경우 제목/설명/OG 이미지를 포함한 링크 프리뷰를 보여준다.
- 링크 프리뷰 카드를 클릭하면 macOS, Windows, iOS에서 기본 브라우저로 해당 링크를 연다.

## v0.3.45 macOS/Windows 수정

- macOS 업데이트/재실행 뒤 Dock에 Ping 아이콘이 남지 않도록 agent 앱 분류와 런타임 accessory 정책을 함께 적용한다.
- 영상 푸시 알림 전달 상태를 서버 `notified_at`으로 기록해 앱 재실행 후 같은 영상 알림이 다시 뜨지 않게 한다.
- 기존 히스토리 캐시에 남은 영상/썸네일 ID를 시작 시 알림 원장에 흡수해 과거에 조회한 영상 알림 재발을 줄인다.

## v0.3.44 macOS/Windows 수정

- Supabase Free 플랜 사용량을 줄이기 위해 영상/초대/룸 폴링 간격을 늘리고, 불필요한 반복 다운로드 경로를 줄였다.
- macOS는 영상 알림 클릭 전 MP4를 안정 캐시에 사전 다운로드하고, 히스토리 썸네일도 디스크 캐시해 다시 열 때 Storage를 덜 호출한다.
- 이미 룸에서 조회한 수신 영상은 앱 재시작 후 푸시 알림으로 다시 오지 않도록 로컬 알림 원장과 서버 알림 RPC를 함께 보강했다.
- 영상 메시지 서버 보존기간은 30일로 유지한다.

## v0.3.43 macOS/Windows 수정

- 룸을 열었을 때 읽지 않은 배지가 즉시 사라지도록 macOS와 Windows의 로컬 룸 상태를 갱신한다.
- 서버의 룸 읽음 RPC가 채팅 읽음 시각뿐 아니라 수신 영상 메시지의 unread 상태도 함께 정리하도록 수정했다.

## v0.3.42 macOS/Windows 수정

- 룸 리스트에서 룸 순서를 수동으로 바꿀 수 있게 했다.
- 새 알림이 있는 룸은 목록 상단에 올라오고, 읽지 않은 메시지 수가 뱃지로 표시된다.
- 서버 룸 목록 RPC를 갱신해 macOS, Windows, iOS가 같은 unread 우선순위와 사용자별 수동 순서를 공유한다.

## v0.3.41 macOS 수정

- 룸 이름을 macOS, Windows, iOS에서 같은 서버 기준 이름으로 표시하도록 맞췄다.
- 사용자가 직접 이름을 바꾸지 않은 룸은 참여자 닉네임 목록을 기본 이름으로 사용한다.

## v0.3.30 Windows 수정

- macOS와 같은 화면+얼굴 재생 크기, 둥근 미디어 표면, 트레이/수신 재생 동작을 반영했다.
- 열린 룸이 새 메시지와 룸 이름 변경을 더 안정적으로 갱신하도록 보강했다.

## v0.3.39 macOS 수정

- 메뉴바 앱 동작은 유지한다. Dock에 절대 표시되지 않아야 하므로 현재 빌드는 번들 `LSUIElement` agent 분류와 런타임 accessory 정책을 함께 적용한다.

## v0.3.29 Windows 수정

- Windows 설치 프로그램과 MSIX 배포 버전을 v0.3.29로 갱신했다. 기능 변경은 없으며 macOS v0.3.39 릴리즈와 함께 다운로드 메타데이터를 맞췄다.

## v0.3.38 macOS 수정

- 송신 거울에서 `Esc 닫기` 가이드를 함께 표시해 Option+P/Option+L 상태에서 닫기 단축키를 알 수 있게 했다.
- 여러 룸이 있을 때 체크박스로 복수 룸을 선택해 같은 영상 메시지를 보낼 수 있게 했다.
- 수신 재생창에서 첫 재생 후 `Enter 다시 재생`과 `Esc 닫기` 가이드를 표시해 재생창이 잠시 남아 있는 이유를 알 수 있게 했다.

## v0.3.34 macOS 수정

- 오너 전용 인앱 다중 계정 전환 기능을 추가했다. 닉네임을 `영민`으로 설정하면 설정 → 일반에 "계정" 섹션이 나타나, 한 기기에서 여러 익명 계정을 보관·전환하고 전환 시 비활성 동안 밀린 알림(영상·초대·채팅)을 모아 볼 수 있다. 세션은 기기에 로컬 저장되어 타인에게 자격증명이 노출되지 않는다.
- 0.3.33 빌드가 이 기능 머지 이전 트리에서 만들어져 실제 앱에는 기능이 빠져 있던 문제를 바로잡았다. 릴리스 빌드는 이제 `main`에서만 실행되도록 가드를 두고, 웹 다운로드와 README의 DMG 참조를 빌드 버전으로 자동 스탬핑한다.
- 설정 닉네임 입력 필드 오른쪽의 "저장" 버튼이 패널 경계에서 잘리던 레이아웃을 수정했다.

## v0.3.33 macOS 수정

- Apple Developer Program 가입 후 릴리스 빌드를 ad-hoc 서명에서 **Developer ID Application 서명 + Apple 공증(notarization) + 스테이플**로 전환했다. 이제 DMG를 받아 실행할 때 "확인되지 않은 개발자" 경고 없이 바로 열린다(`spctl` 판정: `accepted / Notarized Developer ID`).
- Developer ID designated requirement는 팀 + 번들 ID에 앵커링되어 빌드마다 안정적이므로, 이전의 ad-hoc requirement 고정 없이도 업데이트 후 TCC 권한이 유지된다.

## v0.3.32 macOS 수정

- 영상 메시지 삭제 RPC가 Supabase Storage 테이블을 SQL에서 직접 삭제하려다 403으로 실패하던 문제를 수정했다.
- 보낸 영상 메시지는 서버 RPC로 룸 히스토리 행을 먼저 삭제하고, 영상 파일은 앱에서 Supabase Storage API로 best-effort 정리한다.

## v0.3.31 macOS 수정

- 영상 메시지 삭제 여부를 서버의 `auth.uid()` 기준으로 판정한다. 보낸 메시지는 모든 수신자 행을 삭제하고, 받은 메시지는 본인에게만 숨긴다.
- 0.3.30에서 로컬 계정 상태가 삭제 분기와 어긋나면 보낸 메시지가 실제 룸 히스토리에 남던 문제를 수정했다.

## v0.3.30 macOS 수정

- macOS에서 보낸 영상 메시지를 삭제하면 같은 영상 객체를 공유하는 모든 수신자 행을 함께 삭제한다.
- macOS 화면+얼굴 메시지를 확대해 둔 상태에서 삭제해도 확대 overlay가 남지 않도록 정리한다.

## v0.3.29 macOS 수정

- macOS 내 룸에서 공유된 사진을 클릭하면 큰 팝업으로 볼 수 있다.
- macOS Option+L 화면+얼굴 녹화에 마이크 오디오 트랙을 포함한다.
- macOS 녹화 리뷰 루프에서 오디오가 들리도록 재생한다.

## v0.3.28 수정

- Sparkle scheduled update 감지 시 같은 업데이트 버전은 한 번만 알리고, 더 최신 버전이 나오면 기존 업데이트 알림을 최신 버전 알림 하나로 교체한다.
- Sparkle installer helper와 통신하는 sandbox mach-lookup 예외를 추가하고, 릴리즈 서명 단계가 Sparkle 내부 helper entitlements를 덮어쓰지 않도록 수정했다.

## v0.3.27 수정

- 하나의 룸에서 여러 채팅 알림이 쌓여도 해당 룸을 열면 같은 룸의 전달된 알림을 함께 정리한다.
- Option+O로 내 룸을 열 때 최신 메시지 위치로 스크롤되도록 로딩 직후 스크롤 타이밍을 보강했다.
- 내 룸 채팅 입력은 Enter로 전송하고 Shift+Enter로 줄바꿈한다.
- 채팅방에서 사진 버튼 선택과 드래그 앤 드롭으로 사진 메시지를 보낼 수 있다.

## v0.3.26 수정

- 화면+얼굴 메시지의 확대 재생 크기를 더 키웠다.
- 확대 시 영상 하단이 보이도록 자동으로 스크롤해 사용자가 직접 내려야 하는 불편을 줄였다.

## v0.3.25 수정

- 내 룸에서 화면+얼굴 메시지를 확대할 때 영상이 사라지던 문제를 수정했다.
- 확장된 화면+얼굴 영상은 사이드바 폭을 줄이지 않고 룸 매니저 최상위 레이어에서 사이드바 위로 표시된다.

## v0.3.24 수정

- 화면+얼굴 메시지의 우측 하단 얼굴 크기를 프리뷰와 실제 저장 영상에서 같은 비율로 유지하도록 수정했다.
- 내 룸 히스토리에서 화면+얼굴 메시지를 확대 재생할 때 사이드바 폭은 유지하고 영상이 사이드바 위로 확장되어 전체 화면이 잘리지 않게 했다.
- 발신자가 상대방의 로컬 저장 허용 여부를 제어하는 저장 권한 설정을 반영했다.

## v0.3.16 수정

- 내 룸 히스토리에서 타임스탬프 swipe reveal이 손을 떼면 자동으로 원위치로 돌아온다.
- 룸 매니저의 새 룸/룸 찾기 툴바 액션이 사이드바 상태와 무관하게 윈도우 우측에 고정된다.
- 룸 매니저 사이드바는 더 컴팩트한 폭을 기본으로 쓰고, 룸 이름은 16자로 제한된다.
- 히스토리 영상 썸네일과 인라인 재생이 로컬 sent/received 아카이브를 먼저 사용한다.

## v0.3.17 수정

- 트랙패드 타임스탬프 reveal이 손을 떼는 즉시 복귀하고 관성 스크롤에 끌려가지 않는다.
- reveal 중 타임스탬프는 말풍선과 함께 밀리지 않고 우측 고정 lane에 표시된다.
- reveal 이벤트가 수직 관성 스크롤을 가로채거나 reset 애니메이션을 반복 시작하지 않도록 해 룸 히스토리 렉을 줄였다.
- 히스토리 영상 인라인 플레이어가 고정 크기를 유지해 썸네일 클릭 후 영상 영역이 사라지지 않는다.
- 히스토리 영상 확장 크기를 키우고, 클릭 시 튀는 느낌 없이 그대로 커지는 ease-out 모션을 적용했다.
- 인라인 영상 레이어 업데이트가 메인 큐에 누적되지 않도록 bounds 변경 시에만 동기 갱신한다.
- 인라인 영상은 실제 표시 크기가 잡힌 뒤 0초부터 재생을 시작해 짧은 영상이 끝 프레임부터 보이지 않게 했다.
- trackpad release/cancel 이벤트가 delta 0으로 들어와도 타임스탬프 reveal을 즉시 닫는다.
- 룸 히스토리 창 기본 크기를 현재 QA에 맞춘 컴팩트한 폭과 높이로 조정했다.
- 마지막 메시지가 입력 필드에 붙지 않도록 히스토리 리스트 하단 여백을 확보했다.

## v0.3.21 수정

- 히스토리 영상 클릭 후 썸네일 영역이 비어 있고 재생이 시작되지 않던 회귀를 수정했다.
- 인라인 영상 플레이어는 SwiftUI 업데이트 호출이 아니라 AppKit view layout에서 layer 크기를 맞춘 뒤 0초부터 재생해, 영상 클릭 후 CPU가 100%로 도는 레이아웃 루프를 막는다.
- 3명 이상 룸에서는 상대가 보낸 영상 메시지에도 보낸 사람 닉네임을 표시한다.
- 다크모드 룸 히스토리에서 날짜 구간이 전체 폭 배경 바처럼 보이던 문제를 제거했다.
- 온보딩 권한 화면의 상단 헤더 위치와 progress 게이지를 고정하고, 권한 체크 UI를 더 컴팩트한 상태 중심 레이아웃으로 재구성했다.
- 화면 녹화 권한은 macOS 설정에서만 켤 수 있음을 명확히 표시하고, 알림 요청 창이 보이지 않을 때 시스템 설정 안내를 보여준다.

## v0.3.23 수정

- 온보딩 권한 화면에서 macOS 권한 재확인이 지연돼도 나머지 3~7단계 QA/설정을 계속 진행할 수 있게 했다.
- 릴리즈 앱의 ad-hoc designated requirement를 bundle id 기준으로 고정해 업데이트 후 TCC 권한 판정이 빌드 해시 변화에 흔들리지 않도록 했다.
- 카메라/마이크 권한 요청이 시스템 프롬프트 없이 멈추는 경우 버튼이 영구히 "확인 중"에 남지 않도록 timeout fallback을 추가했다.

## v0.3.22 수정

- 온보딩 화면 전환 시 상단 헤더와 progress 위치가 움직이지 않도록 고정 크기 레이아웃으로 정리했다.
- 권한 화면을 0/4 카운터와 긴 설명 없이 4개 항목만 보이는 미니멀 체크리스트로 단순화했다.
- 앱 시작 시 알림 권한 프롬프트를 먼저 소모하지 않도록 바꿔, 온보딩의 알림 `허용` 버튼이 실제 요청을 담당한다.
- 화면 녹화 권한 확인은 시스템 프롬프트를 띄우지 않는 CoreGraphics 사전 체크만 사용하고, macOS가 요구하는 앱 재시작 안내를 명확히 표시한다.

## 시스템 요구사항

- macOS 13 Ventura 이상
- Apple Silicon Mac 권장
- Windows 11 24H2 이상
- Windows App SDK 2.1.3, .NET 10, Visual Studio C++ desktop toolchain은 Windows 클라이언트 빌드에 필요
