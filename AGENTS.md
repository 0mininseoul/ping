# AGENTS.md — Codex / Claude Code 진입점

이 파일은 코딩 에이전트(Codex CLI, Claude Code 등)가 프로젝트 작업을 시작할 때 가장 먼저 읽어야 하는 문서입니다.

---

## 0. 가장 중요한 규칙

### 🚨 다음 4가지 항목을 절대로 "다운그레이드"하거나 "교체"하지 마세요

학습 데이터 시점이 macOS 26 / Swift 6 / Apple Liquid Glass API 이전이라 모를 수 있지만, **이들은 모두 실재하는 최신 정식 API입니다**. 본인이 모른다고 해서 구식 API로 바꾸지 마세요.

| 항목 | 상태 | 절대 하지 말 것 |
|---|---|---|
| **macOS 26 (Tahoe)** | 2025년 가을 정식 출시 | `macOS 14` / `15` 로 deploymentTarget 낮추지 말 것 |
| **Swift 6.0+** | 정식 릴리스 | `Swift 5.x` 로 SWIFT_VERSION 낮추지 말 것 |
| **`.glassEffect()` SwiftUI modifier** | macOS 26 네이티브 Liquid Glass material | `.background(.regularMaterial)` 또는 `NSVisualEffectView` 로 교체하지 말 것 |
| **`SMAppService.mainApp`** | macOS 13+ 모던 자동 시작 API | 구식 `LaunchAgent` plist 방식으로 바꾸지 말 것 |

**API가 컴파일되지 않으면** Xcode Command Line Tools가 구버전인 것입니다. 사용자에게 `xcode-select --install` 또는 Xcode 16+ 업데이트를 요청하세요. **API를 바꾸지 말고 도구를 업데이트하라는 메시지로 멈추세요.**

---

## 1. 프로젝트 개요

**Ping** — macOS 26 Tahoe 전용 2초 영상 메시지 메뉴바 앱. Option+P로 즉시 카메라 원형 거울이 뜨고, Enter로 정확히 2초 녹화하여 Firebase 경유로 파트너에게 전송. 수신자는 발신자가 지정한 위치에 그대로 2초간 재생.

### 핵심 문서 (반드시 모두 읽고 작업 시작)
1. **`PING_PROJECT_SPECIFICATION.md`** — 기능/아키텍처/보안 명세 (v2.0)
2. **`docs/superpowers/plans/2026-05-17-ping-mvp.md`** — Day 1~7 bite-sized 구현 플랜
3. (본 파일) **`AGENTS.md`** — 본 에이전트 진입점

새 세션을 시작할 때마다 위 3개 파일을 모두 읽고 컨텍스트를 복원하세요.

---

## 2. 단일 진실 출처 (Single Source of Truth)

다음 값들은 여러 파일에 동시에 존재합니다. **하나를 바꾸면 모든 곳을 함께 업데이트해야 합니다.**

### Bundle ID — `com.youngminpark.ping.Ping`
- `project.yml` → `options.bundleIdPrefix: com.youngminpark.ping` + target 이름 `Ping`
- Firebase 콘솔 Apple platforms 앱 등록 시 입력값
- `Resources/GoogleService-Info.plist` 내부 `BUNDLE_ID` 필드

**Bundle ID 한 곳이 어긋나면 Firebase Auth가 런타임에 실패하고 빌드는 통과하므로 디버깅이 매우 어렵습니다.**

### Firebase Project ID — `<YOUR_FIREBASE_PROJECT_ID>` (placeholder)
플랜의 `ping-mvp` 는 예시일 뿐, **사용자가 실제 생성한 Firebase 프로젝트 ID를 사용해야 합니다.** 다음 위치에 동일하게 들어갑니다:
- `firebase.json` (firebase CLI가 자동 관리)
- `.firebaserc` (firebase CLI가 자동 관리)
- 모든 `firebase deploy --project <ID>` 명령
- `gsutil` 명령의 버킷 URL: `gs://<ID>.firebasestorage.app/`

사용자에게 처음 한 번 물어보고 그 값을 모든 곳에 일관되게 적용하세요. 임의로 `ping-mvp` 로 두지 마세요.

### Storage 버킷 도메인
Firebase가 2024년 이후 생성된 프로젝트는 `<projectId>.firebasestorage.app`, 이전은 `<projectId>.appspot.com` 을 사용합니다. **확실하지 않으면 Firebase 콘솔 Storage 페이지에서 정확한 버킷 URL을 확인하고 그 값을 사용하세요.**

### App 버전 — `0.1.0`
- `project.yml` → `settings.base.MARKETING_VERSION`
- `scripts/build-release.sh` → 빌드 산출물 자동 추출
- `README.md` 의 DMG 파일명 예시
- `git tag` v0.1.0

---

## 3. 개발 환경

### 필수 설치 도구 (사전 확인)
```bash
xcode-select -p                    # /Applications/Xcode.app/Contents/Developer 또는 CLT 경로
xcodebuild -version                # Xcode 16.0+ (Swift 6 컴파일러 포함)
swift --version                    # Swift 6.0+
brew install xcodegen create-dmg   # 누락 시 즉시 설치
npm install -g firebase-tools      # firebase CLI
brew install --cask google-cloud-sdk   # gsutil (Storage Lifecycle 설정용)
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
├── PING_PROJECT_SPECIFICATION.md    # 변경 시 v2.0 → v2.1 등 버전 표시
├── AGENTS.md                        # 본 파일
├── README.md                        # 최종 사용자용 설치 가이드
├── docs/superpowers/
│   ├── specs/                       # 추가 design doc 들어갈 자리
│   └── plans/                       # 구현 플랜
├── project.yml                      # XcodeGen 스펙 — 직접 .xcodeproj 편집 금지
├── Package.swift                    # SPM 명시 필요 시
├── firebase.json                    # firebase CLI 관리
├── firestore.rules                  # 직접 편집
├── storage.rules                    # 직접 편집
├── firestore.indexes.json           # 직접 편집
├── Ping.entitlements                # 직접 편집 또는 project.yml 동기화
├── Ping/                            # 앱 소스 (자세한 구조는 spec 참조)
├── PingTests/                       # 단위 테스트
├── Resources/                       # 앱 번들 리소스 (Assets, GoogleService-Info.plist 등)
├── design/mockups/                  # frontend-design 산출물 (HTML/CSS)
├── scripts/
│   └── build-release.sh             # Release 빌드 + ad-hoc 서명 + DMG
├── build/                           # gitignore
└── dist/                            # 배포 산출물 (DMG), gitignore
```

### 절대 하지 말 것
- **`Ping.xcodeproj` 직접 편집 금지** — XcodeGen이 매번 재생성합니다. `project.yml` 만 수정하세요.
- **`Resources/GoogleService-Info.plist` 를 git에 commit하지 마세요** — `.gitignore`에 이미 등록됨.
- **Firebase 콘솔 작업이 필요한 단계는 사용자에게 명시적으로 요청하세요** — 자동화 불가입니다.

---

## 5. 코드 스타일

- **Swift 6 strict concurrency**. `@MainActor` 명시, actor isolation 위반 시 컴파일러 경고 무시하지 말 것.
- **async/await 우선**. Firebase 콜백은 모두 async wrapper로 감쌈.
- **`@ObservableObject`** for SwiftUI view models. `@Observable` macro 도 가능하나 본 프로젝트는 ObservableObject 통일.
- **파일당 한 책임**. 100줄 넘어가면 분리 고려.
- **주석 최소화**. WHY 만 적고 WHAT 은 코드로 표현. 한국어 주석 OK.
- **Commit 메시지**: `<type>(<scope>): <subject>` 형식. type ∈ {feat, fix, chore, docs, test, refactor, release}.

---

## 6. Firebase 권장 사항

- **Anonymous Auth 만 사용** — 이메일/소셜 로그인 추가 금지 (v0.2 이후).
- **Cloud Functions 없음** — 모든 로직은 클라이언트 + Firestore 보안 규칙.
- **TTL/Lifecycle 로 자동 삭제** — `messages` 24h, `invitations` 7d, Storage 영상 24h.
- **보안 규칙 변경 시 즉시 deploy**: `firebase deploy --only firestore:rules,storage:rules --project <PROJECT_ID>`.
- **인덱스 누락 에러는 무시하지 말 것** — Firestore가 에러 메시지에 인덱스 생성 URL을 제공하므로 클릭하여 만들고 `firestore.indexes.json` 에도 반영.

---

## 7. UI 디자인 원칙

- **Liquid Glass (`.glassEffect()`)** 가 기본. macOS 26 표준 material이라 별도 라이브러리 불필요.
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

### Firestore listener의 race condition
`observeIncoming` 의 첫 emit이 "기존 모든 메시지"를 한 번에 던지므로 앱 시작 직후 모든 이전 메시지에 대해 알림이 발생할 수 있습니다. `change.type == .added` 필터만으로는 부족하고, **앱 시작 시점 이후 생성된 메시지인지 `createdAt` 으로 한 번 더 게이팅**해야 합니다. (Day 4 구현 시 주의)

### Sandbox + 글로벌 단축키
`KeyboardShortcuts` 는 Sandbox 안에서 동작합니다. 만약 단축키가 안 잡히면 entitlements 의 `com.apple.security.app-sandbox` 를 의심하기 전에 **시스템 설정 → 개인정보 보호 및 보안 → 입력 모니터링** 권한을 먼저 확인하세요.

---

## 9. 자주 묻는 질문

**Q: 빌드는 되는데 Firebase가 동작 안 합니다.**
A: 1) `GoogleService-Info.plist` 가 `Resources/` 에 있는지, 2) 그 파일의 `BUNDLE_ID` 가 빌드된 앱의 Bundle ID와 일치하는지, 3) Firebase 콘솔에서 Anonymous Auth 가 활성화됐는지 확인.

**Q: `.glassEffect()` 가 unknown identifier 라고 합니다.**
A: Xcode Command Line Tools 가 macOS 26 SDK를 포함하지 않은 구버전입니다. Xcode 16+ 를 설치하거나 `xcode-select` 로 경로를 바꾸세요. **API를 다른 것으로 교체하지 마세요.**

**Q: 단위 테스트에서 Firebase import 가 안 됩니다.**
A: `project.yml` 의 `PingTests` target에 Firebase 패키지 의존성을 추가하거나, `@testable import Ping` 만 쓰고 Firebase 직접 import는 피하세요.

**Q: `xcodegen generate` 후 빌드가 깨집니다.**
A: 1) `xcodebuild clean` 후 재빌드, 2) `.swiftpm/` 및 `Ping.xcodeproj` 삭제 후 재생성, 3) `Package.resolved` 가 stale 가능하므로 삭제.

**Q: DMG 첫 실행 시 "확인되지 않은 개발자" 경고가 뜹니다.**
A: ad-hoc 서명이라 정상입니다. **우클릭 → 열기 → 다시 열기** 로 한 번 우회하면 이후 일반 실행됩니다. README에 안내됨.

---

## 10. 작업 시작 전 체크리스트

새 세션에서 코딩 시작 전 다음을 확인:

- [ ] `PING_PROJECT_SPECIFICATION.md` (v2.0) 전체 읽음
- [ ] `docs/superpowers/plans/2026-05-17-ping-mvp.md` 의 해당 Day/Task 읽음
- [ ] 본 `AGENTS.md` 의 "절대 하지 말 것" 4가지 숙지
- [ ] `git status` 깨끗한가? 또는 어디까지 진행됐는가?
- [ ] 사용자가 Firebase 프로젝트를 만들었는가? Project ID, Bundle ID 확인됨?
- [ ] 필수 도구(xcodegen, create-dmg, firebase, gsutil) 모두 설치됨?

준비 OK면 플랜의 해당 Task부터 진행하세요.
