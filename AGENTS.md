# AGENTS.md — Codex / Claude Code 진입점

이 파일은 코딩 에이전트(Codex CLI, Claude Code 등)가 프로젝트 작업을 시작할 때 가장 먼저 읽어야 하는 문서입니다.

---

## 0. 가장 중요한 규칙

### 🚨 다음 4가지 제품 불변식을 절대로 "다운그레이드"하거나 "교체"하지 마세요

Ping은 v0.1.4부터 **macOS 13 Ventura 이상**을 지원합니다. 학습 데이터 시점이 Swift 6 / Apple Liquid Glass API 이전이라 모를 수 있지만, **이들은 모두 실재하는 최신 정식 API입니다**. 본인이 모른다고 해서 구식 API로 바꾸지 마세요.

| 항목 | 상태 | 절대 하지 말 것 |
|---|---|---|
| **macOS 13 Ventura 이상** | v0.1.4부터 지원 | `MACOSX_DEPLOYMENT_TARGET` 또는 `LSMinimumSystemVersion`을 `13.0` 아래로 낮추지 말 것 |
| **Swift 6.0+** | 정식 릴리스 | `Swift 5.x` 로 SWIFT_VERSION 낮추지 말 것 |
| **`.pingGlassEffect()` wrapper** | macOS 26 Tahoe에서는 `.glassEffect()`, macOS 13-25에서는 안정 tint fallback | `Ping/UI/Glass/GlassEffectCompat.swift` 밖에서 `.glassEffect()`를 직접 호출하지 말 것 |
| **`SMAppService.mainApp`** | macOS 13+ 모던 자동 시작 API | 구식 `LaunchAgent` plist 방식으로 바꾸지 말 것 |

**`.glassEffect()`가 compat 파일 안에서 컴파일되지 않으면** Xcode Command Line Tools가 구버전인 것입니다. 사용자에게 `xcode-select --install` 또는 Xcode 16+ 업데이트를 요청하세요. **API를 바꾸지 말고 도구를 업데이트하라는 메시지로 멈추세요.**

---

## 1. 프로젝트 개요

**Ping** — macOS 13 Ventura 이상에서 동작하는 3초 영상 메시지 메뉴바 앱. Option+P로 얼굴만 거울, Option+L로 화면+얼굴 거울이 뜨고, Enter로 녹화한 뒤 리뷰 화면에서 승인해 Supabase 경유로 파트너에게 전송. 수신자는 발신자가 지정한 위치에 그대로 재생한다.

### 핵심 문서 (반드시 모두 읽고 작업 시작)
1. **`PING_PROJECT_SPECIFICATION.md`** — 기능/아키텍처/보안 명세 (v2.3)
2. **`docs/superpowers/plans/2026-05-17-ping-mvp.md`** — Day 1~7 bite-sized 구현 플랜
3. (본 파일) **`AGENTS.md`** — 본 에이전트 진입점

새 세션을 시작할 때마다 위 3개 파일을 모두 읽고 컨텍스트를 복원하세요.

---

## 2. 단일 진실 출처 (Single Source of Truth)

다음 값들은 여러 파일에 동시에 존재합니다. **하나를 바꾸면 모든 곳을 함께 업데이트해야 합니다.**

### Bundle ID — `com.youngminpark.ping.Ping`
- `project.yml` → `options.bundleIdPrefix: com.youngminpark.ping` + target 이름 `Ping`

Bundle ID는 macOS 권한과 앱 식별의 기준이므로 임의 변경하지 마세요.

### Supabase 설정
현재 구현은 Supabase Free 플랜 기준입니다. 앱 런타임에는 `Resources/Supabase.plist`가 필요하고, 이 파일은 git에 커밋하지 않습니다. 형식은 `Resources/Supabase.example.plist`를 따릅니다.

Supabase CLI 작업은 `npx supabase`로 수행합니다. 새 계정/프로젝트에 링크하려면 `npx supabase login --no-browser` 또는 `npx supabase link --project-ref <ref>`가 필요합니다.

### Supabase Free 저장소
영상은 Supabase Storage의 비공개 `ping-videos` 버킷에 `<senderUid>/<videoId>.mp4` 경로로 저장합니다. 테이블/RLS/RPC/Storage 정책은 `supabase/migrations/20260517000100_create_ping_backend.sql`이 단일 진실 출처입니다. 서버 예약 작업 없이 앱 실행 시 `ping_cleanup_expired_data()` RPC로 만료 데이터를 best-effort 정리합니다.

### App 버전 — `0.3.32`
- `project.yml` → `settings.base.MARKETING_VERSION`
- `scripts/build-release.sh` → 빌드 산출물 자동 추출
- `README.md` 의 DMG 파일명 예시
- release tag는 해당 버전 배포 시 생성

---

## 3. 개발 환경

### 필수 설치 도구 (사전 확인)
```bash
xcode-select -p                    # /Applications/Xcode.app/Contents/Developer 또는 CLT 경로
xcodebuild -version                # Xcode 16.0+ (Swift 6 컴파일러 포함)
swift --version                    # Swift 6.0+
brew install xcodegen create-dmg   # 누락 시 즉시 설치
npx supabase --version             # Supabase CLI
```

### 빌드/실행 사이클
```bash
# 1. project.yml 또는 dependencies 변경 시
xcodegen generate

# 2. 디버그 빌드
xcodebuild -project Ping.xcodeproj -scheme Ping -configuration Debug \
           -destination "platform=macOS" build

# 3. 실행
DERIVED=$(xcodebuild -project Ping.xcodeproj -scheme Ping -showBuildSettings \
          | grep -m1 BUILT_PRODUCTS_DIR | awk '{print $3}')
open "$DERIVED/Ping.app"

# 4. 종료 (정상)
osascript -e 'tell application "Ping" to quit'

# 5. 종료 (강제 — 위 명령이 hang 되거나 거울이 키 입력 잡고 있을 때)
pkill -f "Ping.app/Contents/MacOS/Ping" || true

# 6. 테스트
xcodebuild -project Ping.xcodeproj -scheme Ping \
           -destination "platform=macOS" test
```

### 권장 작업 흐름
1. **TDD 가능 영역** (`Core/`, 순수 함수): 테스트 먼저 → 실패 확인 → 구현 → 통과 → commit.
2. **UI/Backend 영역**: 작은 단위로 구현 → `xcodebuild build` 로 컴파일 검증 → 수동 smoke test → commit.
3. **매 Task 종료 시점에 반드시 git commit.** Task 사이에 작업물을 누적하지 마세요. 플랜에 명시된 commit 메시지를 그대로 사용하세요.

---

## 4. 디렉터리 구조 규약

```
ping/
├── PING_PROJECT_SPECIFICATION.md    # 변경 시 v2.3 → v2.4 등 버전 표시
├── AGENTS.md                        # 본 파일
├── README.md                        # 최종 사용자용 설치 가이드
├── docs/superpowers/
│   ├── specs/                       # 추가 design doc 들어갈 자리
│   └── plans/                       # 구현 플랜
├── project.yml                      # XcodeGen 스펙 — 직접 .xcodeproj 편집 금지
├── Package.swift                    # SPM 명시 필요 시
├── supabase/                        # Supabase CLI config + migrations
├── Ping.entitlements                # 직접 편집 또는 project.yml 동기화
├── Ping/                            # 앱 소스 (자세한 구조는 spec 참조)
├── PingTests/                       # 단위 테스트
├── Resources/                       # 앱 번들 리소스 (Assets, Supabase.example.plist 등)
├── design/mockups/                  # frontend-design 산출물 (HTML/CSS)
├── scripts/
│   └── build-release.sh             # Release 빌드 + ad-hoc 서명 + DMG
├── build/                           # gitignore
└── dist/                            # 배포 산출물 (DMG), gitignore
```

### 절대 하지 말 것
- **`Ping.xcodeproj` 직접 편집 금지** — XcodeGen이 매번 재생성합니다. `project.yml` 만 수정하세요.
- **`Resources/Supabase.plist` 를 git에 commit하지 마세요** — `.gitignore`에 이미 등록됨.
- **Supabase 원격 프로젝트 링크/로그인이 필요한 단계는 사용자에게 명시적으로 요청하세요** — 새 계정 인증이 필요할 수 있습니다.

---

## 5. 코드 스타일

- **Swift 6 strict concurrency**. `@MainActor` 명시, actor isolation 위반 시 컴파일러 경고 무시하지 말 것.
- **async/await 우선**. Supabase 통신은 `URLSession` REST/RPC wrapper로 통일.
- **`@ObservableObject`** for SwiftUI view models. `@Observable` macro 도 가능하나 본 프로젝트는 ObservableObject 통일.
- **파일당 한 책임**. 100줄 넘어가면 분리 고려.
- **주석 최소화**. WHY 만 적고 WHAT 은 코드로 표현. 한국어 주석 OK.
- **Commit 메시지**: `<type>(<scope>): <subject>` 형식. type ∈ {feat, fix, chore, docs, test, refactor, release}.

---

## 6. Supabase 권장 사항

- **Anonymous Auth 만 사용** — 이메일/소셜 로그인 추가 금지 (v0.2 이후).
- **Edge Functions 없음** — 무료 플랜 유지와 단순성을 위해 클라이언트 + Postgres RPC + RLS로 처리.
- **Storage는 비공개 버킷** — `ping-videos` 객체는 소유자 prefix 업로드, 메시지 sender/receiver 읽기 정책으로 제한.
- **마이그레이션 변경 시 즉시 적용**: `npx supabase db push`.
- **RPC 인자 이름을 Swift 호출과 맞출 것** — PostgREST named args라 SQL 인자명 변경은 런타임 오류로 이어집니다.

---

## 7. UI 디자인 원칙

- **Liquid Glass는 `.pingGlassEffect()` wrapper를 통해서만 적용**. macOS 26 Tahoe에서는 네이티브 `.glassEffect()`, macOS 13-25에서는 `PingDesign.Surface` 기반 안정 tint fallback을 사용한다.
- **시스템 폰트만 사용** — SF Pro / Apple SD Gothic Neo 자동 fallback. 커스텀 폰트 번들링 금지.
- **거울/재생창은 원형**, 카드/패널은 16pt 라운드.
- **상태별 보더 색 일관성**:
  - 대기: `Color.white.opacity(0.30)`, 1pt
  - 녹화: `#FF3B30` (system red), 2pt
  - 실패: `#FFCC00` (system yellow), 2pt
  - 전체 발송: `RainbowBorder` (회전 그라데이션), 2pt
- **송신 완료 시 별도 toast/문구 표시 금지** — 윈도우만 fade-out. 이건 의도적 UX 결정입니다.

---

## 8. 알려진 함정 (이전 세션의 교훈)

### `MirrorPosition` 재정의 함정 (Day 2 → Day 3)
Day 2 Task 2.1에서 `Ping/Core/Models.swift` 에 `MirrorPosition` 만 정의합니다. Day 3 Task 3.1에서 같은 파일을 **"Replace"** 하라고 합니다. 이때 새 정의에 `MirrorPosition` 이 포함되어 있으니 기존 것을 보존하려 하지 마세요. **파일 전체를 새 내용으로 교체**하면 됩니다.

### XcodeGen 의 entitlements 파일 경로
`project.yml` 에 `entitlements: properties: ...` 로 적으면 XcodeGen이 entitlements 파일을 **자동 생성**합니다. 생성 경로는 일반적으로 프로젝트 루트의 `Ping.entitlements` 이지만, XcodeGen 버전에 따라 `Ping/Ping.entitlements` 일 수도 있습니다. **빌드 스크립트(`scripts/build-release.sh`) 의 `--entitlements` 경로가 실제 생성 위치와 일치하는지 첫 빌드 시 반드시 확인**하세요.

### `MirrorWindow(rootView: EmptyView())` 패턴
Day 4 Task 4.3 에서 임시 EmptyView로 윈도우를 만든 뒤 `contentView` 를 NSHostingView로 교체합니다. 이는 `MirrorView` 클로저가 `windowOrigin` 을 참조해야 해서 윈도우 인스턴스가 먼저 필요하기 때문입니다. **"이상하다"고 단순화하지 마세요.** 윈도우 self-reference의 순환 의존 해결 패턴입니다.

### CameraManager는 단일 인스턴스
`AVCaptureSession` 을 여러 번 만들면 카메라 충돌이 발생합니다. AppDelegate가 보유한 **단일 `CameraManager` 인스턴스를 MirrorView에 주입** 하세요.

### Supabase polling의 중복 알림
현재 MVP는 Supabase Realtime 대신 2초 polling으로 `messages`/`rooms`/`invitations`를 읽습니다. `observeIncoming`은 세션 내 `yieldedIds`와 앱 전역 `notifiedMessageIds`로 중복 알림을 막으므로 이 방어를 제거하지 마세요.

### Sparkle 자동 업데이트
앱은 Sparkle 2로 자동 업데이트한다. `project.yml`의 `SUPublicEDKey`는 빌드 머신 Keychain에 있는 EdDSA 개인키와 짝을 이뤄야 한다. `Ping/Info.plist`는 XcodeGen 산출물이므로 직접 편집하지 말 것. 한 번도 셋업이 안 된 환경이라면 `docs/AUTO_UPDATE_SETUP.md` 의 1~2단계를 먼저 실행해야 빌드가 의미 있는 appcast를 만든다. `SUFeedURL`을 임의로 바꾸지 말 것 — `https://ping0min.vercel.app/appcast.xml` 이 단일 진실 출처다.

### Supabase 세션 저장과 Keychain 팝업
앱 런타임의 Supabase Anonymous Auth 세션은 sandboxed Application Support의 `SupabaseSession.json`에 저장한다. ad-hoc 서명 앱을 `/Applications/Ping.app`로 자주 교체하면 기존 Keychain 항목 ACL이 "Ping이 저장된 비밀 정보를 사용하려고 합니다" 승인 팝업을 띄울 수 있으므로, `SupabaseSessionStore`의 자동 load/save/clear 경로에 `SecItem*` 호출을 다시 넣지 마세요. Sparkle appcast 서명용 Keychain 개인키는 별도 개념이다.

### Sandbox + 글로벌 단축키
`KeyboardShortcuts` 는 Sandbox 안에서 동작합니다. 만약 단축키가 안 잡히면 entitlements 의 `com.apple.security.app-sandbox` 를 의심하기 전에 **시스템 설정 → 개인정보 보호 및 보안 → 입력 모니터링** 권한을 먼저 확인하세요.

---

## 9. 자주 묻는 질문

**Q: 빌드는 되는데 Supabase가 동작 안 합니다.**
A: 1) `Resources/Supabase.plist` 가 있는지, 2) `SUPABASE_URL`/`SUPABASE_ANON_KEY`가 맞는지, 3) Supabase Dashboard에서 Anonymous sign-ins가 활성화됐는지, 4) `npx supabase db push`가 적용됐는지 확인.

**Q: `.glassEffect()` 가 unknown identifier 라고 합니다.**
A: `Ping/UI/Glass/GlassEffectCompat.swift` 를 컴파일하는 Xcode Command Line Tools 가 macOS 26 SDK를 포함하지 않은 구버전입니다. Xcode 16+ 를 설치하거나 `xcode-select` 로 경로를 바꾸세요. **API를 다른 것으로 교체하지 말고 `.pingGlassEffect()` wrapper를 유지하세요.**

**Q: 단위 테스트에서 네트워크 요청이 나갑니다.**
A: `AppDelegate`는 `XCTestConfigurationFilePath` 환경에서 bootstrap을 건너뜁니다. 이 방어를 유지하세요.

**Q: `xcodegen generate` 후 빌드가 깨집니다.**
A: 1) `xcodebuild clean` 후 재빌드, 2) `.swiftpm/` 및 `Ping.xcodeproj` 삭제 후 재생성, 3) `Package.resolved` 가 stale 가능하므로 삭제.

**Q: DMG 첫 실행 시 "확인되지 않은 개발자" 경고가 뜹니다.**
A: ad-hoc 서명이라 정상입니다. **우클릭 → 열기 → 다시 열기** 로 한 번 우회하면 이후 일반 실행됩니다. README에 안내됨.

---

## 10. 작업 시작 전 체크리스트

새 세션에서 코딩 시작 전 다음을 확인:

- [ ] `PING_PROJECT_SPECIFICATION.md` (v2.3) 전체 읽음
- [ ] `docs/superpowers/plans/2026-05-17-ping-mvp.md` 의 해당 Day/Task 읽음
- [ ] 본 `AGENTS.md` 의 "절대 하지 말 것" 4가지 숙지
- [ ] `git status` 깨끗한가? 또는 어디까지 진행됐는가?
- [ ] 사용자가 Supabase 프로젝트를 만들었는가? Project URL, anon key, project ref 확인됨?
- [ ] 필수 도구(xcodegen, create-dmg, npx supabase) 모두 설치됨?

준비 OK면 플랜의 해당 Task부터 진행하세요.
