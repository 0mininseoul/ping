# macOS 자동 시작 + 자동 복구(KeepAlive) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Ping.app이 로그인 시 자동으로 켜지고, macOS `cache_delete`의 강제 종료나 크래시로 꺼져도 launchd가 수 초 안에 되살리게 한다.

**Architecture:** 앱 번들 안(`Contents/Library/LaunchAgents/`)에 LaunchAgent plist를 넣고 `SMAppService.agent(plistName:)`로 등록해 프로세스 수명을 launchd에 맡긴다. `KeepAlive = { SuccessfulExit: false }`가 비정상 종료만 골라 재실행하므로 사용자가 메뉴바에서 "종료"한 경우는 되살아나지 않는다. 등록 여부 결정은 순수 함수(`AutoStartPolicy`)로 분리하고, `SMAppService`를 실제로 호출하는 곳은 `AutoStartController` 한 곳으로 모은다.

**Tech Stack:** Swift 6 / SwiftUI / AppKit, ServiceManagement (`SMAppService`, macOS 13+), XcodeGen(`project.yml`), XCTest

**설계 문서:** `docs/superpowers/specs/2026-08-04-macos-autostart-keepalive-design.md`

## Global Constraints

- **배포 타깃 macOS 13.0.** `SMAppService.agent(plistName:)`는 macOS 13+ API라 그대로 쓸 수 있다. macOS 14+ 전용 API(`NSRunningApplication.activate()` 무인자 버전 등)는 쓰지 않는다.
- **앱은 샌드박스 상태다** (`Ping.entitlements`의 `com.apple.security.app-sandbox: true`). `SMAppService`는 샌드박스에서 동작하는 API이므로 entitlements 변경은 필요 없다. entitlements 파일을 건드리지 말 것.
- **설정 UI의 문구·레이아웃을 바꾸지 않는다.** 토글 제목은 `"로그인 시 자동 시작"` 그대로, 상태 문구 `"켜져 있음"` / `"시스템 설정에서 승인이 필요합니다."` / `"꺼져 있음"` / `"자동 시작 항목을 찾을 수 없습니다."` / `"상태를 확인할 수 없습니다."` 그대로, 오류 문구 `"자동 시작 설정을 변경하지 못했습니다."` 그대로. 바꾸는 것은 배선뿐이다.
- **`userChoice == false`를 코드가 뒤집는 경로를 만들지 않는다.** 사용자가 껐는데 업데이트마다 다시 켜지면 악성 동작이다.
- **LaunchAgent 식별자는 `com.youngminpark.ping.Ping.keepalive`**, plist 파일명은 `com.youngminpark.ping.Ping.keepalive.plist`. 앱 번들 ID는 `com.youngminpark.ping.Ping`.
- **빌드 명령** (AGENTS.md 규약):
  ```bash
  xcodegen generate      # project.yml 변경 시
  xcodebuild -project Ping.xcodeproj -scheme Ping -configuration Debug -destination "platform=macOS" build
  xcodebuild -project Ping.xcodeproj -scheme Ping -destination "platform=macOS" test
  ```
- **PingTests는 호스트 앱이 없는 유닛 테스트 번들이다.** 소스 파일이나 plist의 내용을 검사하는 "contract test"는 `project.yml`의 `Copy Contract Test Fixtures` 스크립트로 파일을 테스트 번들 Resources에 복사한 뒤 `Bundle(for: Self.self).resourceURL`에서 읽는다. 새 fixture가 필요하면 그 스크립트의 `cp` 줄과 `inputFiles` 목록에 **둘 다** 추가해야 한다.
- **커밋 메시지 규약:** `type(scope): summary` (예: `feat(autostart): ...`). 각 커밋 끝에 `Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>` 한 줄.
- **브랜치:** `feat/macos-autostart-keepalive` (이미 생성됨, 스펙 커밋 `515a26d` 위에 쌓는다).

---

## File Structure

| 파일 | 책임 |
|---|---|
| `Resources/LaunchAgents/com.youngminpark.ping.Ping.keepalive.plist` | launchd 잡 정의. 재실행 정책의 유일한 선언 지점 |
| `Ping/Core/AutoStart/AutoStartPolicy.swift` | (userChoice, agentStatus, mainAppStatus) → action. 순수 함수. 프레임워크 의존 없음 |
| `Ping/Core/AutoStart/LaunchLedger.swift` | 단명 기동 카운트 + 크래시 루프 임계값 판정 |
| `Ping/Core/AutoStart/SingleInstanceGuard.swift` | 중복 인스턴스 판정 + 러닝앱 조회 어댑터 |
| `Ping/Core/AutoStart/AutoStartController.swift` | 위 셋을 엮고 `SMAppService`를 호출하는 **유일한** 지점 |
| `Ping/AppDelegate.swift` | 기동 훅: 중복 가드 → 원장 기록 → 정책 적용 → 60초 후 healthy 표시 |
| `Ping/UI/Setup/SettingsScene.swift` | 토글 배선만 controller로 교체 |
| `Ping/Core/UserPreferences.swift` | UserDefaults 키 2개 추가 |
| `Ping/Notifications/LocalNotificationCenter.swift` | 크래시 루프로 자동 시작을 껐을 때의 알림 1종 추가 |

---

## Task 1: LaunchAgent plist와 번들 통합

plist를 만들고 앱 번들의 `Contents/Library/LaunchAgents/`에 서명 포함된 상태로 들어가게 한다. 이 태스크는 코드를 부르지 않는다 — 파일이 올바른 자리에 올바른 내용으로 들어갔는지만 보장한다.

**Files:**
- Create: `Resources/LaunchAgents/com.youngminpark.ping.Ping.keepalive.plist`
- Modify: `project.yml` (Ping 타깃 `sources`에 copyFiles 빌드 페이즈 추가 / PingTests `Copy Contract Test Fixtures`에 fixture 추가)
- Test: `PingTests/AutoStartAgentPlistTests.swift`

**Interfaces:**
- Consumes: 없음 (첫 태스크)
- Produces: 번들 경로 `Contents/Library/LaunchAgents/com.youngminpark.ping.Ping.keepalive.plist`, 잡 Label `com.youngminpark.ping.Ping.keepalive`. Task 5의 `AutoStartController.agentPlistName`이 이 파일명을 참조한다.

- [ ] **Step 1: plist 작성**

`Resources/LaunchAgents/com.youngminpark.ping.Ping.keepalive.plist`:

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>Label</key>
	<string>com.youngminpark.ping.Ping.keepalive</string>
	<key>BundleProgram</key>
	<string>Contents/MacOS/Ping</string>
	<key>RunAtLoad</key>
	<true/>
	<key>KeepAlive</key>
	<dict>
		<key>SuccessfulExit</key>
		<false/>
	</dict>
	<key>ThrottleInterval</key>
	<integer>30</integer>
	<key>AssociatedBundleIdentifiers</key>
	<array>
		<string>com.youngminpark.ping.Ping</string>
	</array>
</dict>
</plist>
```

각 키의 의미(변경하지 말 것):
- `BundleProgram` — 앱 번들 기준 **상대 경로**. `/Applications/Ping.app/...` 절대 경로를 쓰면 사용자가 앱을 옮겼을 때 깨진다.
- `KeepAlive.SuccessfulExit = false` — 비정상 종료(`cache_delete`의 `0xBADDD15C`, 크래시)일 때만 재실행. 사용자가 메뉴바에서 "종료"하면 `exit(0)`이라 재실행하지 않는다.
- `ThrottleInterval 30` — 기동 즉시 죽는 병리 상태에서 launchd가 초당 수십 번 재시도하는 것을 막는다.

- [ ] **Step 2: 실패하는 contract test 작성**

`PingTests/AutoStartAgentPlistTests.swift`:

```swift
import XCTest

final class AutoStartAgentPlistTests: XCTestCase {
    func testAgentRelaunchesOnlyOnAbnormalExit() throws {
        let plist = try readPlist("com.youngminpark.ping.Ping.keepalive.plist")
        let keepAlive = try XCTUnwrap(plist["KeepAlive"] as? [String: Any])

        // 사용자가 "종료"하면 exit(0)이므로 되살아나면 안 된다.
        XCTAssertEqual(keepAlive["SuccessfulExit"] as? Bool, false)
        XCTAssertEqual(plist["RunAtLoad"] as? Bool, true)
    }

    func testAgentUsesBundleRelativeProgramPath() throws {
        let plist = try readPlist("com.youngminpark.ping.Ping.keepalive.plist")

        // 절대 경로면 앱을 옮겼을 때 깨진다.
        XCTAssertEqual(plist["BundleProgram"] as? String, "Contents/MacOS/Ping")
        XCTAssertNil(plist["ProgramArguments"])
    }

    func testAgentIdentityMatchesController() throws {
        let plist = try readPlist("com.youngminpark.ping.Ping.keepalive.plist")

        XCTAssertEqual(plist["Label"] as? String, "com.youngminpark.ping.Ping.keepalive")
        XCTAssertEqual(plist["ThrottleInterval"] as? Int, 30)
        XCTAssertEqual(
            plist["AssociatedBundleIdentifiers"] as? [String],
            ["com.youngminpark.ping.Ping"]
        )
    }

    func testProjectBundlesAgentIntoLaunchAgentsDirectory() throws {
        let project = try readSourceFile("project.yml")

        XCTAssertTrue(project.contains("subpath: Contents/Library/LaunchAgents"))
        XCTAssertTrue(project.contains("Resources/LaunchAgents/com.youngminpark.ping.Ping.keepalive.plist"))
    }

    private func readPlist(_ relativePath: String) throws -> [String: Any] {
        let data = try Data(contentsOf: resourceURL(for: relativePath))
        let plist = try PropertyListSerialization.propertyList(from: data, format: nil)

        return try XCTUnwrap(plist as? [String: Any])
    }

    private func readSourceFile(_ relativePath: String) throws -> String {
        try String(contentsOf: resourceURL(for: relativePath), encoding: .utf8)
    }

    private func resourceURL(for relativePath: String) throws -> URL {
        let fileName = URL(fileURLWithPath: relativePath).lastPathComponent
        return try XCTUnwrap(Bundle(for: Self.self).resourceURL?.appendingPathComponent(fileName))
    }
}
```

- [ ] **Step 3: 테스트가 실패하는지 확인**

```bash
xcodegen generate
xcodebuild -project Ping.xcodeproj -scheme Ping -destination "platform=macOS" test \
  -only-testing:PingTests/AutoStartAgentPlistTests
```
Expected: FAIL — fixture가 아직 복사되지 않아 `resourceURL`이 가리키는 파일이 없다.

- [ ] **Step 4: project.yml에 번들 복사 페이즈 추가**

`Ping` 타깃의 `sources:` 블록을 다음과 같이 바꾼다 (기존 `- path: Ping` 줄은 유지):

```yaml
    sources:
      - path: Ping
      - path: Resources/LaunchAgents/com.youngminpark.ping.Ping.keepalive.plist
        buildPhase:
          copyFiles:
            destination: wrapper
            subpath: Contents/Library/LaunchAgents
```

- [ ] **Step 5: project.yml의 테스트 fixture 목록에 추가**

`PingTests` 타깃 `Copy Contract Test Fixtures` 스크립트에서, `cp "$PROJECT_DIR/project.yml" "$DST/project.yml"` 줄 **바로 앞에** 다음을 추가한다:

```bash
          cp "$PROJECT_DIR/Resources/LaunchAgents/com.youngminpark.ping.Ping.keepalive.plist" "$DST/com.youngminpark.ping.Ping.keepalive.plist"
```

그리고 같은 스크립트의 `inputFiles:` 목록 끝에 다음을 추가한다:

```yaml
          - "$(PROJECT_DIR)/Resources/LaunchAgents/com.youngminpark.ping.Ping.keepalive.plist"
```

`project.yml`은 이미 fixture로 복사되고 있으므로 `testProjectBundlesAgentIntoLaunchAgentsDirectory`는 추가 설정 없이 동작한다.

- [ ] **Step 6: 테스트 통과 확인**

```bash
xcodegen generate
xcodebuild -project Ping.xcodeproj -scheme Ping -destination "platform=macOS" test \
  -only-testing:PingTests/AutoStartAgentPlistTests
```
Expected: PASS (4개 테스트)

- [ ] **Step 7: 번들 안에 실제로 들어갔고 서명이 유효한지 확인**

```bash
xcodebuild -project Ping.xcodeproj -scheme Ping -configuration Debug -destination "platform=macOS" build
DERIVED=$(xcodebuild -project Ping.xcodeproj -scheme Ping -showBuildSettings \
          | grep -m1 BUILT_PRODUCTS_DIR | awk '{print $3}')
ls -l "$DERIVED/Ping.app/Contents/Library/LaunchAgents/"
codesign --verify --deep --strict "$DERIVED/Ping.app" && echo "SIGNATURE OK"
```
Expected: plist 파일이 보이고 `SIGNATURE OK` 출력.

**서명이 깨지면**: Copy Files 페이즈가 코드 서명 페이즈보다 뒤에 실행된 것이다. Xcode 프로젝트에서 빌드 페이즈 순서를 확인하고, XcodeGen이 페이즈를 뒤에 붙였다면 `project.yml`의 해당 source 항목을 `sources` 목록 **맨 앞**으로 옮겨 재생성한다.

- [ ] **Step 8: 커밋**

```bash
git add Resources/LaunchAgents/com.youngminpark.ping.Ping.keepalive.plist project.yml PingTests/AutoStartAgentPlistTests.swift Ping.xcodeproj
git commit -m "$(cat <<'EOF'
feat(autostart): bundle KeepAlive LaunchAgent into the app

KeepAlive={SuccessfulExit:false} so launchd relaunches only on abnormal
exit — cache_delete's 0xBADDD15C kill and crashes come back, a user-
initiated quit does not.

Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>
EOF
)"
```

---

## Task 2: AutoStartPolicy — 등록 여부 결정 (순수 함수)

`SMAppService`를 부르지 않고 "무엇을 해야 하는가"만 정하는 순수 함수. 이 태스크의 산출물은 전부 단위 테스트로 검증된다.

**Files:**
- Create: `Ping/Core/AutoStart/AutoStartPolicy.swift`
- Test: `PingTests/AutoStartPolicyTests.swift`

**Interfaces:**
- Consumes: 없음
- Produces:
  - `enum AutoStartStatus: Equatable { case enabled, requiresApproval, notRegistered, notFound, unknown }` + `var isRegistered: Bool`
  - `enum AutoStartAction: Equatable { case none, registerAgent, unregisterAgent, migrateFromMainApp }`
  - `enum AutoStartPolicy { static func action(userChoice: Bool?, agentStatus: AutoStartStatus, mainAppStatus: AutoStartStatus) -> AutoStartAction }`
  - Task 5의 `AutoStartController`가 이 셋을 모두 쓴다.

- [ ] **Step 1: 실패하는 테스트 작성**

`PingTests/AutoStartPolicyTests.swift`:

```swift
import XCTest
@testable import Ping

final class AutoStartPolicyTests: XCTestCase {
    private let allStatuses: [AutoStartStatus] = [.enabled, .requiresApproval, .notRegistered, .notFound, .unknown]

    // MARK: userChoice == nil — 기본 ON

    func testFirstRunRegistersAgent() {
        let action = AutoStartPolicy.action(
            userChoice: nil,
            agentStatus: .notRegistered,
            mainAppStatus: .notRegistered
        )

        XCTAssertEqual(action, .registerAgent)
    }

    func testFirstRunMigratesWhenLegacyLoginItemIsEnabled() {
        for mainAppStatus in [AutoStartStatus.enabled, .requiresApproval] {
            let action = AutoStartPolicy.action(
                userChoice: nil,
                agentStatus: .notRegistered,
                mainAppStatus: mainAppStatus
            )

            XCTAssertEqual(action, .migrateFromMainApp, "mainAppStatus: \(mainAppStatus)")
        }
    }

    func testFirstRunDoesNothingWhenAgentIsAlreadyEnabled() {
        let action = AutoStartPolicy.action(
            userChoice: nil,
            agentStatus: .enabled,
            mainAppStatus: .notRegistered
        )

        XCTAssertEqual(action, .none)
    }

    // MARK: userChoice == true — 자가 치유

    func testEnabledChoiceReregistersWhenAgentIsMissing() {
        for agentStatus in [AutoStartStatus.notRegistered, .notFound] {
            let action = AutoStartPolicy.action(
                userChoice: true,
                agentStatus: agentStatus,
                mainAppStatus: .notRegistered
            )

            XCTAssertEqual(action, .registerAgent, "agentStatus: \(agentStatus)")
        }
    }

    func testEnabledChoiceRespectsSystemSettingsApprovalState() {
        // requiresApproval은 사용자가 시스템 설정에서 껐다는 뜻이다. 억지로 다시 켜지 않는다.
        let action = AutoStartPolicy.action(
            userChoice: true,
            agentStatus: .requiresApproval,
            mainAppStatus: .notRegistered
        )

        XCTAssertEqual(action, .none)
    }

    // MARK: userChoice == false — 절대 뒤집지 않는다

    func testDisabledChoiceNeverRegisters() {
        for agentStatus in allStatuses {
            for mainAppStatus in allStatuses {
                let action = AutoStartPolicy.action(
                    userChoice: false,
                    agentStatus: agentStatus,
                    mainAppStatus: mainAppStatus
                )

                XCTAssertNotEqual(action, .registerAgent, "\(agentStatus)/\(mainAppStatus)")
                XCTAssertNotEqual(action, .migrateFromMainApp, "\(agentStatus)/\(mainAppStatus)")
            }
        }
    }

    func testDisabledChoiceUnregistersOnlyWhenRegistered() {
        XCTAssertEqual(
            AutoStartPolicy.action(userChoice: false, agentStatus: .enabled, mainAppStatus: .notRegistered),
            .unregisterAgent
        )
        XCTAssertEqual(
            AutoStartPolicy.action(userChoice: false, agentStatus: .notRegistered, mainAppStatus: .notRegistered),
            .none
        )
    }

    // MARK: 마이그레이션은 1회성

    func testLegacyLoginItemIsIgnoredOnceUserChoiceExists() {
        for userChoice in [true, false] {
            for mainAppStatus in allStatuses {
                let withLegacy = AutoStartPolicy.action(
                    userChoice: userChoice,
                    agentStatus: .enabled,
                    mainAppStatus: mainAppStatus
                )
                let withoutLegacy = AutoStartPolicy.action(
                    userChoice: userChoice,
                    agentStatus: .enabled,
                    mainAppStatus: .notRegistered
                )

                XCTAssertEqual(withLegacy, withoutLegacy, "\(userChoice)/\(mainAppStatus)")
            }
        }
    }
}
```

- [ ] **Step 2: 테스트가 실패하는지 확인**

```bash
xcodebuild -project Ping.xcodeproj -scheme Ping -destination "platform=macOS" test \
  -only-testing:PingTests/AutoStartPolicyTests
```
Expected: 컴파일 실패 — `AutoStartStatus` / `AutoStartAction` / `AutoStartPolicy` 미정의.

- [ ] **Step 3: 구현**

`Ping/Core/AutoStart/AutoStartPolicy.swift`:

```swift
import Foundation

/// `SMAppService.Status`를 프레임워크 의존 없이 표현한 값. 정책 판정을 순수 함수로 유지하려고 분리했다.
enum AutoStartStatus: Equatable {
    case enabled
    case requiresApproval
    case notRegistered
    case notFound
    case unknown

    /// 등록된 것으로 취급할 상태. `requiresApproval`은 등록은 되어 있고 사용자 승인만 빠진 상태다.
    var isRegistered: Bool {
        self == .enabled || self == .requiresApproval
    }
}

enum AutoStartAction: Equatable {
    case none
    case registerAgent
    case unregisterAgent
    /// 구 로그인 항목(`SMAppService.mainApp`)을 해제한 뒤 agent를 등록한다. 순서가 중요하다.
    case migrateFromMainApp
}

/// 자동 시작 등록 상태를 어떻게 맞출지 정하는 순수 함수. 부작용이 없어 전수 테스트가 가능하다.
enum AutoStartPolicy {
    static func action(
        userChoice: Bool?,
        agentStatus: AutoStartStatus,
        mainAppStatus: AutoStartStatus
    ) -> AutoStartAction {
        guard let userChoice else {
            // 한 번도 선택한 적 없음 = 신규 설치이거나 업데이트 후 첫 실행. 기본 ON으로 켠다.
            if mainAppStatus.isRegistered {
                return .migrateFromMainApp
            }
            return agentStatus == .enabled ? .none : .registerAgent
        }

        guard userChoice else {
            // 사용자가 명시적으로 껐다. 어떤 상태에서도 다시 켜지 않는다.
            return agentStatus.isRegistered ? .unregisterAgent : .none
        }

        // 앱을 옮겼거나 번들이 교체되면 notFound/notRegistered로 떨어진다. 자가 치유한다.
        switch agentStatus {
        case .enabled, .requiresApproval, .unknown:
            return .none
        case .notRegistered, .notFound:
            return .registerAgent
        }
    }
}
```

- [ ] **Step 4: 테스트 통과 확인**

```bash
xcodegen generate
xcodebuild -project Ping.xcodeproj -scheme Ping -destination "platform=macOS" test \
  -only-testing:PingTests/AutoStartPolicyTests
```
Expected: PASS (7개 테스트)

- [ ] **Step 5: 커밋**

```bash
git add Ping/Core/AutoStart/AutoStartPolicy.swift PingTests/AutoStartPolicyTests.swift Ping.xcodeproj
git commit -m "$(cat <<'EOF'
feat(autostart): add pure AutoStartPolicy decision function

Default-on for first run, one-shot migration off the legacy login item,
self-healing re-register when the bundle moves. A stored userChoice of
false is never reversed.

Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>
EOF
)"
```

---

## Task 3: LaunchLedger — 크래시 루프 차단

앱이 기동 즉시 죽으면 launchd가 30초마다 영원히 되살린다. "60초를 못 넘긴 기동"이 연속 5회면 자동 시작을 스스로 끈다.

**Files:**
- Create: `Ping/Core/AutoStart/LaunchLedger.swift`
- Modify: `Ping/Core/UserPreferences.swift` (`PingPreferenceKeys`에 키 2개 추가)
- Test: `PingTests/LaunchLedgerTests.swift`

**Interfaces:**
- Consumes: 없음
- Produces:
  - `PingPreferenceKeys.autostartUserChoice` = `"ping.autostart.userChoice"`, `PingPreferenceKeys.autostartLaunchLedger` = `"ping.autostart.launchLedger"`
  - `@MainActor struct LaunchLedger { init(defaults: UserDefaults = .standard, threshold: Int = 5); static let healthyLifetime: TimeInterval = 60; var shortLivedLaunchCount: Int; @discardableResult func recordLaunch(at date: Date = Date()) -> Bool; func markHealthy() }`
  - Task 5의 `AutoStartController`가 `recordLaunch` / `markHealthy`를, Task 6의 `AppDelegate`가 `LaunchLedger.healthyLifetime`을 쓴다.

- [ ] **Step 1: 실패하는 테스트 작성**

`PingTests/LaunchLedgerTests.swift`:

```swift
import XCTest
@testable import Ping

@MainActor final class LaunchLedgerTests: XCTestCase {
    private var suiteName: String!
    private var defaults: UserDefaults!

    override func setUpWithError() throws {
        suiteName = "LaunchLedgerTests.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
    }

    override func tearDownWithError() throws {
        defaults.removePersistentDomain(forName: suiteName)
    }

    func testStaysQuietBelowThreshold() {
        let ledger = LaunchLedger(defaults: defaults, threshold: 5)

        for index in 1...4 {
            XCTAssertFalse(ledger.recordLaunch(at: Date()), "launch \(index)")
        }
        XCTAssertEqual(ledger.shortLivedLaunchCount, 4)
    }

    func testTripsAtThreshold() {
        let ledger = LaunchLedger(defaults: defaults, threshold: 5)

        for _ in 1...4 {
            _ = ledger.recordLaunch(at: Date())
        }
        XCTAssertTrue(ledger.recordLaunch(at: Date()))
    }

    func testHealthyRunResetsTheCount() {
        let ledger = LaunchLedger(defaults: defaults, threshold: 5)

        for _ in 1...4 {
            _ = ledger.recordLaunch(at: Date())
        }
        // 60초를 넘겨 살아남은 실행은 카운터를 리셋한다. 수동으로 껐다 켜는 정상 사용이
        // 크래시 루프로 오판되지 않게 하는 장치다.
        ledger.markHealthy()

        XCTAssertEqual(ledger.shortLivedLaunchCount, 0)
        XCTAssertFalse(ledger.recordLaunch(at: Date()))
    }

    func testCountIsCappedAtThreshold() {
        let ledger = LaunchLedger(defaults: defaults, threshold: 5)

        for _ in 1...12 {
            _ = ledger.recordLaunch(at: Date())
        }
        XCTAssertEqual(ledger.shortLivedLaunchCount, 5)
    }

    func testHealthyLifetimeIsOneMinute() {
        XCTAssertEqual(LaunchLedger.healthyLifetime, 60)
    }

    func testPreferenceKeysAreStable() {
        XCTAssertEqual(PingPreferenceKeys.autostartUserChoice, "ping.autostart.userChoice")
        XCTAssertEqual(PingPreferenceKeys.autostartLaunchLedger, "ping.autostart.launchLedger")
    }
}
```

- [ ] **Step 2: 테스트가 실패하는지 확인**

```bash
xcodebuild -project Ping.xcodeproj -scheme Ping -destination "platform=macOS" test \
  -only-testing:PingTests/LaunchLedgerTests
```
Expected: 컴파일 실패 — `LaunchLedger` 및 새 `PingPreferenceKeys` 미정의.

- [ ] **Step 3: UserDefaults 키 추가**

`Ping/Core/UserPreferences.swift`의 `PingPreferenceKeys`에 두 줄을 추가한다 (`appearanceMode` 줄 아래):

```swift
    static let autostartUserChoice = "ping.autostart.userChoice"
    static let autostartLaunchLedger = "ping.autostart.launchLedger"
```

- [ ] **Step 4: LaunchLedger 구현**

`Ping/Core/AutoStart/LaunchLedger.swift`:

```swift
import Foundation

/// launchd KeepAlive가 크래시 루프를 무한 반복하지 않도록 "짧게 살다 죽은 기동"만 센다.
/// 60초를 넘겨 살아남은 실행은 `markHealthy()`로 카운터를 리셋하므로,
/// 사용자가 수동으로 껐다 켜는 정상 사용은 루프로 오판되지 않는다.
@MainActor struct LaunchLedger {
    /// 이 시간을 넘겨 살아 있으면 건강한 실행으로 본다.
    static let healthyLifetime: TimeInterval = 60

    private let defaults: UserDefaults
    private let threshold: Int

    init(defaults: UserDefaults = .standard, threshold: Int = 5) {
        self.defaults = defaults
        self.threshold = threshold
    }

    var shortLivedLaunchCount: Int {
        stamps.count
    }

    /// 기동을 기록하고, 임계값에 도달했으면 true를 돌려준다.
    /// true면 호출자가 자동 시작을 해제해야 한다.
    @discardableResult
    func recordLaunch(at date: Date = Date()) -> Bool {
        var updated = stamps
        updated.append(date.timeIntervalSince1970)
        if updated.count > threshold {
            updated = Array(updated.suffix(threshold))
        }
        defaults.set(updated, forKey: PingPreferenceKeys.autostartLaunchLedger)

        return updated.count >= threshold
    }

    func markHealthy() {
        defaults.removeObject(forKey: PingPreferenceKeys.autostartLaunchLedger)
    }

    private var stamps: [Double] {
        defaults.array(forKey: PingPreferenceKeys.autostartLaunchLedger) as? [Double] ?? []
    }
}
```

- [ ] **Step 5: 테스트 통과 확인**

```bash
xcodegen generate
xcodebuild -project Ping.xcodeproj -scheme Ping -destination "platform=macOS" test \
  -only-testing:PingTests/LaunchLedgerTests
```
Expected: PASS (6개 테스트)

- [ ] **Step 6: 커밋**

```bash
git add Ping/Core/AutoStart/LaunchLedger.swift Ping/Core/UserPreferences.swift PingTests/LaunchLedgerTests.swift Ping.xcodeproj
git commit -m "$(cat <<'EOF'
feat(autostart): add LaunchLedger crash-loop guard

Counts only launches that fail to survive 60 seconds, so a healthy run
resets the counter and manual quit/reopen is not mistaken for a loop.

Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>
EOF
)"
```

---

## Task 4: SingleInstanceGuard — 중복 실행 방지

launchd가 띄운 인스턴스가 있는데 사용자가 Ping.app을 더블클릭하면 메뉴바 아이콘 2개 · realtime 구독 2벌 · 알림 2배가 된다.

**Files:**
- Create: `Ping/Core/AutoStart/SingleInstanceGuard.swift`
- Test: `PingTests/SingleInstanceGuardTests.swift`

**Interfaces:**
- Consumes: 없음
- Produces:
  - `protocol RunningInstanceLocating { func processIdentifiers(forBundleIdentifier bundleIdentifier: String) -> [pid_t] }`
  - `struct WorkspaceInstanceLocator: RunningInstanceLocating` (기본 구현)
  - `enum SingleInstanceGuard { static func shouldYield(runningPIDs: [pid_t], currentPID: pid_t) -> Bool }`
  - Task 6의 `AppDelegate.applicationWillFinishLaunching`이 쓴다.

- [ ] **Step 1: 실패하는 테스트 작성**

`PingTests/SingleInstanceGuardTests.swift`:

```swift
import XCTest
@testable import Ping

final class SingleInstanceGuardTests: XCTestCase {
    func testDoesNotYieldWhenAloneInTheList() {
        XCTAssertFalse(SingleInstanceGuard.shouldYield(runningPIDs: [42], currentPID: 42))
    }

    func testDoesNotYieldWhenListIsEmpty() {
        // LaunchServices 등록 전이면 자기 자신도 목록에 없을 수 있다. 물러나면 앱이 아예 안 뜬다.
        XCTAssertFalse(SingleInstanceGuard.shouldYield(runningPIDs: [], currentPID: 42))
    }

    func testYieldsWhenAnotherInstanceIsAlreadyRunning() {
        // 이 판정은 기동 직후에만 실행되므로 "다른 pid = 나보다 먼저 뜬 인스턴스"가 성립한다.
        XCTAssertTrue(SingleInstanceGuard.shouldYield(runningPIDs: [17, 42], currentPID: 42))
    }

    func testYieldsEvenWhenSelfIsNotYetListed() {
        XCTAssertTrue(SingleInstanceGuard.shouldYield(runningPIDs: [17], currentPID: 42))
    }

    func testLocatorReturnsEmptyForUnknownBundleIdentifier() {
        // 존재하지 않는 번들 ID. 조회가 크래시하지 않고 빈 배열을 주는지 본다.
        let pids = WorkspaceInstanceLocator()
            .processIdentifiers(forBundleIdentifier: "com.youngminpark.ping.NoSuchApp")

        XCTAssertTrue(pids.isEmpty)
    }
}
```

- [ ] **Step 2: 테스트가 실패하는지 확인**

```bash
xcodebuild -project Ping.xcodeproj -scheme Ping -destination "platform=macOS" test \
  -only-testing:PingTests/SingleInstanceGuardTests
```
Expected: 컴파일 실패 — `SingleInstanceGuard` / `WorkspaceInstanceLocator` 미정의.

- [ ] **Step 3: 구현**

`Ping/Core/AutoStart/SingleInstanceGuard.swift`:

```swift
import AppKit
import Foundation

protocol RunningInstanceLocating {
    func processIdentifiers(forBundleIdentifier bundleIdentifier: String) -> [pid_t]
}

struct WorkspaceInstanceLocator: RunningInstanceLocating {
    func processIdentifiers(forBundleIdentifier bundleIdentifier: String) -> [pid_t] {
        NSRunningApplication
            .runningApplications(withBundleIdentifier: bundleIdentifier)
            .map(\.processIdentifier)
    }
}

/// launchd가 띄운 인스턴스와 사용자가 더블클릭한 인스턴스가 겹치면
/// 메뉴바 아이콘 2개·realtime 구독 2벌·알림 2배가 된다. 나중에 뜬 쪽이 물러난다.
enum SingleInstanceGuard {
    /// 이 판정은 `applicationWillFinishLaunching`에서만 호출된다.
    /// 우리 프로세스는 방금 떴으므로 목록의 다른 pid는 전부 우리보다 먼저 뜬 인스턴스다.
    static func shouldYield(runningPIDs: [pid_t], currentPID: pid_t) -> Bool {
        runningPIDs.contains { $0 != currentPID }
    }
}
```

- [ ] **Step 4: 테스트 통과 확인**

```bash
xcodegen generate
xcodebuild -project Ping.xcodeproj -scheme Ping -destination "platform=macOS" test \
  -only-testing:PingTests/SingleInstanceGuardTests
```
Expected: PASS (5개 테스트)

- [ ] **Step 5: 커밋**

```bash
git add Ping/Core/AutoStart/SingleInstanceGuard.swift PingTests/SingleInstanceGuardTests.swift Ping.xcodeproj
git commit -m "$(cat <<'EOF'
feat(autostart): add single-instance guard

Prevents duplicate menu bar icons and doubled realtime subscriptions when
a launchd-started instance and a user-launched one overlap.

Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>
EOF
)"
```

---

## Task 5: AutoStartController — SMAppService를 만지는 유일한 지점

정책·원장을 엮고 실제 등록/해제를 수행한다. 크래시 루프 알림도 여기서 낸다.

**Files:**
- Create: `Ping/Core/AutoStart/AutoStartController.swift`
- Modify: `Ping/Notifications/LocalNotificationCenter.swift` (알림 1종 추가)
- Test: `PingTests/AutoStartControllerTests.swift`

**Interfaces:**
- Consumes: `AutoStartStatus`, `AutoStartAction`, `AutoStartPolicy` (Task 2), `LaunchLedger`, `PingPreferenceKeys.autostartUserChoice` (Task 3)
- Produces:
  - `@MainActor final class AutoStartController`
    - `static let shared: AutoStartController`
    - `static let agentPlistName = "com.youngminpark.ping.Ping.keepalive.plist"`
    - `init(defaults: UserDefaults = .standard)`
    - `var userChoice: Bool? { get set }`
    - `var status: AutoStartStatus { get }`
    - `static func map(_ status: SMAppService.Status) -> AutoStartStatus`
    - `func setEnabled(_ enabled: Bool) throws`
    - `func applyPolicyAtLaunch()`
    - `func recordLaunch(now: Date = Date())`
    - `func markHealthy()`
  - `LocalNotificationCenter.shared.notifyAutoStartDisabled()`
  - Task 6(`AppDelegate`)과 Task 7(`SettingsScene`)이 쓴다.

- [ ] **Step 1: 실패하는 테스트 작성**

`SMAppService` 호출 자체는 단위 테스트가 불가능하다(시스템 등록을 건드린다). 테스트는 **주입된 defaults 위에서의 `userChoice` 영속성**과 **상태 매핑**만 검증한다. 등록/해제 동작은 Task 8의 수동 검증이 담당한다.

`PingTests/AutoStartControllerTests.swift`:

```swift
import ServiceManagement
import XCTest
@testable import Ping

@MainActor final class AutoStartControllerTests: XCTestCase {
    private var suiteName: String!
    private var defaults: UserDefaults!

    override func setUpWithError() throws {
        suiteName = "AutoStartControllerTests.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
    }

    override func tearDownWithError() throws {
        defaults.removePersistentDomain(forName: suiteName)
    }

    func testUserChoiceStartsUnset() {
        let controller = AutoStartController(defaults: defaults)

        XCTAssertNil(controller.userChoice)
    }

    func testUserChoiceRoundTrips() {
        let controller = AutoStartController(defaults: defaults)

        controller.userChoice = true
        XCTAssertEqual(controller.userChoice, true)

        controller.userChoice = false
        XCTAssertEqual(controller.userChoice, false)

        controller.userChoice = nil
        XCTAssertNil(controller.userChoice)
    }

    func testFalseIsDistinguishableFromUnset() {
        // Bool?를 object(forKey:)로 읽지 않고 bool(forKey:)로 읽으면 false와 미설정이 뭉개진다.
        // 그러면 사용자가 끈 상태가 매 기동마다 "첫 실행"으로 오인돼 다시 켜진다.
        let controller = AutoStartController(defaults: defaults)
        controller.userChoice = false

        XCTAssertNotNil(controller.userChoice)
        XCTAssertEqual(controller.userChoice, false)
    }

    func testStatusMappingCoversEveryServiceManagementCase() {
        XCTAssertEqual(AutoStartController.map(.enabled), .enabled)
        XCTAssertEqual(AutoStartController.map(.requiresApproval), .requiresApproval)
        XCTAssertEqual(AutoStartController.map(.notRegistered), .notRegistered)
        XCTAssertEqual(AutoStartController.map(.notFound), .notFound)
    }

    func testAgentPlistNameMatchesBundledFile() {
        XCTAssertEqual(
            AutoStartController.agentPlistName,
            "com.youngminpark.ping.Ping.keepalive.plist"
        )
    }
}
```

- [ ] **Step 2: 테스트가 실패하는지 확인**

```bash
xcodebuild -project Ping.xcodeproj -scheme Ping -destination "platform=macOS" test \
  -only-testing:PingTests/AutoStartControllerTests
```
Expected: 컴파일 실패 — `AutoStartController` 미정의.

- [ ] **Step 3: 크래시 루프 알림 추가**

`Ping/Notifications/LocalNotificationCenter.swift`:

`static let updateAvailableIdentifier = "ping.update.available"` 줄 아래에 추가:

```swift
    static let autoStartDisabledIdentifier = "ping.autostart.disabled"
```

`clearUpdateAvailableNotification()` 메서드 **바로 위에** 추가:

```swift
    func notifyAutoStartDisabled() {
        let content = UNMutableNotificationContent()
        content.title = "Ping 자동 시작을 껐습니다"
        content.body = "앱이 반복해서 비정상 종료되어 자동 시작을 해제했습니다. 설정에서 다시 켤 수 있습니다."
        content.sound = notificationSound()

        let request = UNNotificationRequest(
            identifier: Self.autoStartDisabledIdentifier,
            content: content,
            trigger: nil
        )
        UNUserNotificationCenter.current().add(request, withCompletionHandler: nil)
    }
```

- [ ] **Step 4: AutoStartController 구현**

`Ping/Core/AutoStart/AutoStartController.swift`:

```swift
import Foundation
import OSLog
import ServiceManagement

/// 자동 시작 등록 상태를 관리한다. `SMAppService`를 호출하는 곳은 이 클래스 하나뿐이다.
@MainActor
final class AutoStartController {
    static let shared = AutoStartController()
    static let agentPlistName = "com.youngminpark.ping.Ping.keepalive.plist"

    private let defaults: UserDefaults
    private let ledger: LaunchLedger
    private let logger = Logger(subsystem: "com.youngminpark.ping.Ping", category: "autostart")

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        self.ledger = LaunchLedger(defaults: defaults)
    }

    private var agent: SMAppService {
        SMAppService.agent(plistName: Self.agentPlistName)
    }

    /// nil이면 사용자가 한 번도 선택하지 않았다는 뜻이다.
    /// `bool(forKey:)`는 false와 미설정을 구분하지 못하므로 반드시 `object(forKey:)`로 읽는다.
    var userChoice: Bool? {
        get { defaults.object(forKey: PingPreferenceKeys.autostartUserChoice) as? Bool }
        set {
            if let newValue {
                defaults.set(newValue, forKey: PingPreferenceKeys.autostartUserChoice)
            } else {
                defaults.removeObject(forKey: PingPreferenceKeys.autostartUserChoice)
            }
        }
    }

    var status: AutoStartStatus {
        Self.map(agent.status)
    }

    static func map(_ status: SMAppService.Status) -> AutoStartStatus {
        switch status {
        case .enabled: return .enabled
        case .requiresApproval: return .requiresApproval
        case .notRegistered: return .notRegistered
        case .notFound: return .notFound
        @unknown default: return .unknown
        }
    }

    /// 설정 토글에서 호출한다. 사용자의 명시적 선택을 저장한다.
    func setEnabled(_ enabled: Bool) throws {
        if enabled {
            try agent.register()
        } else if status.isRegistered {
            try agent.unregister()
        }
        userChoice = enabled
    }

    /// 기동 시 1회 호출. 기본 ON 적용과 구 로그인 항목 마이그레이션을 수행한다.
    func applyPolicyAtLaunch() {
        let choice = userChoice
        let action = AutoStartPolicy.action(
            userChoice: choice,
            agentStatus: status,
            mainAppStatus: Self.map(SMAppService.mainApp.status)
        )

        do {
            switch action {
            case .none:
                break
            case .registerAgent:
                try agent.register()
            case .unregisterAgent:
                try agent.unregister()
            case .migrateFromMainApp:
                // 순서가 중요하다. mainApp을 남긴 채 agent를 등록하면 로그인 시 두 번 실행된다.
                try SMAppService.mainApp.unregister()
                try agent.register()
            }

            if choice == nil {
                userChoice = true
            }
        } catch {
            // 실패하면 userChoice를 저장하지 않는다. 다음 기동에서 다시 시도한다.
            logger.error("auto-start \(String(describing: action), privacy: .public) failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    /// 기동을 원장에 기록한다. 연속 단명 기동이 임계값에 닿으면 자동 시작을 스스로 끈다.
    func recordLaunch(now: Date = Date()) {
        guard ledger.recordLaunch(at: now) else { return }
        disableAfterCrashLoop()
    }

    /// 기동 후 `LaunchLedger.healthyLifetime`을 넘겨 살아남았을 때 호출한다.
    func markHealthy() {
        ledger.markHealthy()
    }

    private func disableAfterCrashLoop() {
        logger.error("auto-start disabled after repeated short-lived launches")

        try? agent.unregister()
        userChoice = false
        ledger.markHealthy()
        LocalNotificationCenter.shared.notifyAutoStartDisabled()
    }
}
```

- [ ] **Step 5: 테스트 통과 확인**

```bash
xcodegen generate
xcodebuild -project Ping.xcodeproj -scheme Ping -destination "platform=macOS" test \
  -only-testing:PingTests/AutoStartControllerTests
```
Expected: PASS (6개 테스트)

- [ ] **Step 6: 커밋**

```bash
git add Ping/Core/AutoStart/AutoStartController.swift Ping/Notifications/LocalNotificationCenter.swift PingTests/AutoStartControllerTests.swift Ping.xcodeproj
git commit -m "$(cat <<'EOF'
feat(autostart): add AutoStartController over SMAppService

Single place that touches ServiceManagement: applies the launch policy,
migrates off the legacy login item, and self-disables with a notification
after repeated short-lived launches.

Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>
EOF
)"
```

---

## Task 6: AppDelegate 기동 훅 연결

**Files:**
- Modify: `Ping/AppDelegate.swift` (`applicationWillFinishLaunching` 57-59행, `applicationDidFinishLaunching` 61-80행, `applicationWillTerminate` 91-103행, 프로퍼티 선언부 37-47행)
- Test: `PingTests/AutoStartLaunchHookTests.swift`

**Interfaces:**
- Consumes: `SingleInstanceGuard`, `WorkspaceInstanceLocator` (Task 4), `AutoStartController` (Task 5), `LaunchLedger.healthyLifetime` (Task 3)
- Produces: 없음 (통합 지점)

- [ ] **Step 1: fixture 등록과 실패하는 contract test 작성**

`project.yml`의 `Copy Contract Test Fixtures`에서 `cp "$PROJECT_DIR/Ping/Info.plist" "$DST/Info.plist"` 줄 **바로 앞에** 추가:

```bash
          cp "$PROJECT_DIR/Ping/AppDelegate.swift" "$DST/AppDelegate.swift"
```

같은 스크립트의 `inputFiles:` 목록 끝에 추가:

```yaml
          - "$(PROJECT_DIR)/Ping/AppDelegate.swift"
```

`PingTests/AutoStartLaunchHookTests.swift`:

```swift
import XCTest

final class AutoStartLaunchHookTests: XCTestCase {
    func testGuardRunsBeforeAnythingElseAndExitsCleanly() throws {
        let source = try readSourceFile("AppDelegate.swift")

        XCTAssertTrue(source.contains("SingleInstanceGuard.shouldYield"))
        // exit(0)이어야 launchd가 비정상 종료로 보지 않아 재실행하지 않는다.
        XCTAssertTrue(source.contains("exit(0)"))
    }

    func testLaunchIsRecordedBeforePolicyIsApplied() throws {
        let source = try readSourceFile("AppDelegate.swift")

        let recordIndex = try XCTUnwrap(source.range(of: "AutoStartController.shared.recordLaunch()")).lowerBound
        let applyIndex = try XCTUnwrap(source.range(of: "AutoStartController.shared.applyPolicyAtLaunch()")).lowerBound

        // 크래시 루프가 감지되면 recordLaunch가 userChoice를 false로 내린다.
        // 그 뒤에 정책을 적용해야 해제 상태가 유지된다.
        XCTAssertLessThan(recordIndex, applyIndex)
    }

    func testHealthyMarkIsScheduled() throws {
        let source = try readSourceFile("AppDelegate.swift")

        XCTAssertTrue(source.contains("LaunchLedger.healthyLifetime"))
        XCTAssertTrue(source.contains("AutoStartController.shared.markHealthy()"))
    }

    func testAutoStartIsSkippedUnderUnitTests() throws {
        let source = try readSourceFile("AppDelegate.swift")

        XCTAssertTrue(source.contains("isRunningUnitTests"))
    }

    private func readSourceFile(_ relativePath: String) throws -> String {
        try String(contentsOf: resourceURL(for: relativePath), encoding: .utf8)
    }

    private func resourceURL(for relativePath: String) throws -> URL {
        let fileName = URL(fileURLWithPath: relativePath).lastPathComponent
        return try XCTUnwrap(Bundle(for: Self.self).resourceURL?.appendingPathComponent(fileName))
    }
}
```

- [ ] **Step 2: 테스트가 실패하는지 확인**

```bash
xcodegen generate
xcodebuild -project Ping.xcodeproj -scheme Ping -destination "platform=macOS" test \
  -only-testing:PingTests/AutoStartLaunchHookTests
```
Expected: 앞의 3개 FAIL (`AppDelegate.swift`에 아직 해당 호출들이 없다), `testAutoStartIsSkippedUnderUnitTests`는 PASS (기존 코드에 이미 `isRunningUnitTests`가 있다 — 이 테스트는 회귀 방지용이다).

- [ ] **Step 3: 프로퍼티 추가**

`Ping/AppDelegate.swift`의 `private var cameraStartTask: Task<Void, Never>?` 줄 아래에 추가:

```swift
    private var autoStartHealthTask: Task<Void, Never>?
```

- [ ] **Step 4: 중복 인스턴스 가드 추가**

`applicationWillFinishLaunching`(57행)을 다음으로 교체:

```swift
    func applicationWillFinishLaunching(_ notification: Notification) {
        if !ProcessInfo.processInfo.isRunningUnitTests, shouldYieldToRunningInstance() {
            // exit(0)이어야 launchd가 비정상 종료로 보지 않는다. 종료 코드가 0이 아니면
            // KeepAlive가 곧바로 다시 띄워 무한 루프가 된다.
            exit(0)
        }

        enforceAccessoryActivationPolicy()
    }

    private func shouldYieldToRunningInstance() -> Bool {
        guard let bundleIdentifier = Bundle.main.bundleIdentifier else { return false }

        return SingleInstanceGuard.shouldYield(
            runningPIDs: WorkspaceInstanceLocator().processIdentifiers(forBundleIdentifier: bundleIdentifier),
            currentPID: ProcessInfo.processInfo.processIdentifier
        )
    }
```

- [ ] **Step 5: 기동 정책 적용 추가**

`applicationDidFinishLaunching`의 `if !ProcessInfo.processInfo.isRunningUnitTests {` 블록(71행)을 다음으로 교체:

```swift
        if !ProcessInfo.processInfo.isRunningUnitTests {
            // 순서 주의: recordLaunch가 크래시 루프를 감지하면 userChoice를 false로 내린다.
            // 그 결과를 applyPolicyAtLaunch가 읽어야 해제 상태가 유지된다.
            AutoStartController.shared.recordLaunch()
            AutoStartController.shared.applyPolicyAtLaunch()
            scheduleAutoStartHealthyMark()

            if showsOnboardingForQA {
                showOnboardingPreviewForQA()
                return
            }

            UpdaterController.shared.start()
            startBootstrapTaskIfNeeded()
        }
```

같은 파일의 `applicationWillTerminate` 아래(105행 `application(_:open:)` 앞)에 추가:

```swift
    private func scheduleAutoStartHealthyMark() {
        autoStartHealthTask?.cancel()
        autoStartHealthTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: UInt64(LaunchLedger.healthyLifetime * 1_000_000_000))
            guard !Task.isCancelled else { return }

            AutoStartController.shared.markHealthy()
        }
    }
```

- [ ] **Step 6: 종료 시 태스크 취소**

`applicationWillTerminate`의 `cameraStartTask?.cancel()` 줄 아래에 추가:

```swift
        autoStartHealthTask?.cancel()
```

- [ ] **Step 7: 테스트 통과 확인**

```bash
xcodegen generate
xcodebuild -project Ping.xcodeproj -scheme Ping -destination "platform=macOS" test \
  -only-testing:PingTests/AutoStartLaunchHookTests
```
Expected: PASS (4개 테스트)

- [ ] **Step 8: 전체 테스트로 회귀 확인**

```bash
xcodebuild -project Ping.xcodeproj -scheme Ping -destination "platform=macOS" test
```
Expected: 전부 PASS. 기존 테스트가 깨지면 진행하지 말고 원인을 보고할 것.

- [ ] **Step 9: 커밋**

```bash
git add Ping/AppDelegate.swift project.yml PingTests/AutoStartLaunchHookTests.swift Ping.xcodeproj
git commit -m "$(cat <<'EOF'
feat(autostart): wire launch hooks into AppDelegate

Yield to an already-running instance with exit(0), record the launch,
apply the auto-start policy, and clear the crash-loop ledger once the
process survives its first minute.

Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>
EOF
)"
```

---

## Task 7: 설정 토글 배선 교체 (문구 불변)

토글이 구 로그인 항목 대신 KeepAlive agent를 조작하게 한다. **화면에 보이는 문구와 레이아웃은 한 글자도 바꾸지 않는다.**

**Files:**
- Modify: `Ping/UI/Setup/SettingsScene.swift` (3행 import, 321-341행 `updateAutoLaunch`/`refreshAutoLaunchStatus`, 380-404행 `isAutoLaunchEnabled`/`autoLaunchStatusText`)
- Test: `PingTests/AutoStartSettingsWiringTests.swift`

**Interfaces:**
- Consumes: `AutoStartController` (Task 5)
- Produces: 없음

`SettingsScene.swift`는 이미 `Copy Contract Test Fixtures`에 등록돼 있으므로 fixture 추가 작업이 필요 없다.

- [ ] **Step 1: 실패하는 테스트 작성**

`PingTests/AutoStartSettingsWiringTests.swift`:

```swift
import XCTest

final class AutoStartSettingsWiringTests: XCTestCase {
    func testToggleDrivesKeepAliveAgentInsteadOfLoginItem() throws {
        let source = try readSourceFile("SettingsScene.swift")

        // mainApp을 남겨두면 agent와 함께 등록돼 로그인 시 두 번 실행된다.
        XCTAssertFalse(source.contains("SMAppService.mainApp"))
        XCTAssertTrue(source.contains("AutoStartController.shared.setEnabled"))
    }

    func testSettingsCopyIsUnchanged() throws {
        let source = try readSourceFile("SettingsScene.swift")

        XCTAssertTrue(source.contains("title: \"로그인 시 자동 시작\""))
        XCTAssertTrue(source.contains("\"켜져 있음\""))
        XCTAssertTrue(source.contains("\"시스템 설정에서 승인이 필요합니다.\""))
        XCTAssertTrue(source.contains("\"꺼져 있음\""))
        XCTAssertTrue(source.contains("\"자동 시작 항목을 찾을 수 없습니다.\""))
        XCTAssertTrue(source.contains("\"상태를 확인할 수 없습니다.\""))
        XCTAssertTrue(source.contains("\"자동 시작 설정을 변경하지 못했습니다.\""))
    }

    private func readSourceFile(_ relativePath: String) throws -> String {
        try String(contentsOf: resourceURL(for: relativePath), encoding: .utf8)
    }

    private func resourceURL(for relativePath: String) throws -> URL {
        let fileName = URL(fileURLWithPath: relativePath).lastPathComponent
        return try XCTUnwrap(Bundle(for: Self.self).resourceURL?.appendingPathComponent(fileName))
    }
}
```

- [ ] **Step 2: 테스트가 실패하는지 확인**

```bash
xcodebuild -project Ping.xcodeproj -scheme Ping -destination "platform=macOS" test \
  -only-testing:PingTests/AutoStartSettingsWiringTests
```
Expected: `testToggleDrivesKeepAliveAgentInsteadOfLoginItem` FAIL (아직 `SMAppService.mainApp` 사용 중), `testSettingsCopyIsUnchanged` PASS.

- [ ] **Step 3: `updateAutoLaunch` 교체**

`Ping/UI/Setup/SettingsScene.swift`의 `updateAutoLaunch(_:)`(321-336행)를 다음으로 교체:

```swift
    private func updateAutoLaunch(_ enabled: Bool) {
        autoLaunchError = nil

        do {
            try AutoStartController.shared.setEnabled(enabled)
        } catch {
            autoLaunchError = "자동 시작 설정을 변경하지 못했습니다."
        }

        refreshAutoLaunchStatus()
    }
```

- [ ] **Step 4: 상태 조회 두 개 교체**

`isAutoLaunchEnabled()`(380-389행)와 `autoLaunchStatusText()`(391-404행)를 다음으로 교체:

```swift
    @MainActor
    private static func isAutoLaunchEnabled() -> Bool {
        AutoStartController.shared.status.isRegistered
    }

    @MainActor
    private static func autoLaunchStatusText() -> String {
        switch AutoStartController.shared.status {
        case .enabled:
            return "켜져 있음"
        case .requiresApproval:
            return "시스템 설정에서 승인이 필요합니다."
        case .notRegistered:
            return "꺼져 있음"
        case .notFound:
            return "자동 시작 항목을 찾을 수 없습니다."
        case .unknown:
            return "상태를 확인할 수 없습니다."
        }
    }
```

- [ ] **Step 5: 쓰이지 않는 import 제거**

`SettingsScene.swift` 3행의 `import ServiceManagement`를 삭제한다. 이 파일에서 `SMAppService`를 더 이상 참조하지 않는다.

- [ ] **Step 6: 테스트 통과 확인**

```bash
xcodegen generate
xcodebuild -project Ping.xcodeproj -scheme Ping -destination "platform=macOS" test \
  -only-testing:PingTests/AutoStartSettingsWiringTests
```
Expected: PASS (2개 테스트)

**`@State` 초기화에서 `@MainActor` 격리 오류가 나면**: `@State private var autoLaunchEnabled = Self.isAutoLaunchEnabled()`(76-77행)를 `@State private var autoLaunchEnabled = false` / `@State private var autoLaunchStatusText = ""`로 바꾸고, 뷰의 `body`에 `.onAppear { refreshAutoLaunchStatus() }`를 추가한다. 표시 문구는 그대로 유지된다.

- [ ] **Step 7: 전체 테스트**

```bash
xcodebuild -project Ping.xcodeproj -scheme Ping -destination "platform=macOS" test
```
Expected: 전부 PASS.

- [ ] **Step 8: 커밋**

```bash
git add Ping/UI/Setup/SettingsScene.swift PingTests/AutoStartSettingsWiringTests.swift Ping.xcodeproj
git commit -m "$(cat <<'EOF'
fix(autostart): point the settings toggle at the KeepAlive agent

Registering mainApp alongside the agent would launch Ping twice at login.
Visible copy and layout are unchanged — only the wiring moved.

Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>
EOF
)"
```

---

## Task 8: 실기기 검증과 스펙 보강

`SMAppService` 등록·launchd 재실행은 단위 테스트로 검증할 수 없다. 실제로 돌려서 확인한다. **이 태스크는 사람이 결과를 읽고 판단해야 하며, 실패 시 그대로 보고한다.**

**Files:**
- Modify: `docs/superpowers/specs/2026-08-04-macos-autostart-keepalive-design.md` (§9에 한계 1건 추가)

**Interfaces:**
- Consumes: Task 1-7 전부
- Produces: 검증 결과 보고

- [ ] **Step 1: 릴리스 빌드와 설치**

```bash
xcodegen generate
xcodebuild -project Ping.xcodeproj -scheme Ping -configuration Debug -destination "platform=macOS" build
DERIVED=$(xcodebuild -project Ping.xcodeproj -scheme Ping -showBuildSettings \
          | grep -m1 BUILT_PRODUCTS_DIR | awk '{print $3}')
codesign --verify --deep --strict "$DERIVED/Ping.app" && echo "SIGNATURE OK"
```

기존 실행 중인 Ping을 먼저 내린다:
```bash
osascript -e 'tell application "Ping" to quit' || pkill -f "Ping.app/Contents/MacOS/Ping" || true
```

- [ ] **Step 2: `BundleProgram` 해석 검증 (가장 불확실한 지점)**

빌드된 앱을 실행한 뒤:

```bash
open "$DERIVED/Ping.app"
sleep 5
launchctl print "gui/$(id -u)/com.youngminpark.ping.Ping.keepalive"
```

Expected: 잡이 출력되고 `program` 또는 `path`가 실제 앱 실행 파일을 가리킨다. `state = running`.

**실패 시 (잡을 못 찾거나 program 경로가 비어 있음)**: `BundleProgram`이 기대대로 해석되지 않은 것이다. 진행을 멈추고 다음을 보고할 것 — `launchctl print` 전체 출력, `SMAppService.agent(...).status` 값, Console.app의 `com.apple.xpc.launchd` 로그. 폴백은 plist를 `ProgramArguments` 절대 경로(`/Applications/Ping.app/Contents/MacOS/Ping`)로 바꾸고 "앱이 /Applications에 있어야 한다"는 제약을 문서화하는 것이지만, **임의로 적용하지 말고 먼저 보고할 것.**

- [ ] **Step 3: 비정상 종료 → 재실행 확인**

```bash
PID=$(pgrep -f "Ping.app/Contents/MacOS/Ping")
echo "before: $PID"
kill -9 "$PID"
sleep 40
echo "after: $(pgrep -f 'Ping.app/Contents/MacOS/Ping')"
```

Expected: 40초 안에 **다른 pid**로 프로세스가 살아 있다. (`ThrottleInterval 30` 때문에 최대 30초가 걸린다.)

- [ ] **Step 4: 정상 종료 → 재실행 안 되는지 확인**

```bash
osascript -e 'tell application "Ping" to quit'
sleep 45
pgrep -f "Ping.app/Contents/MacOS/Ping" || echo "STAYED DOWN (correct)"
```

Expected: `STAYED DOWN (correct)`. 여기서 앱이 되살아나면 `KeepAlive.SuccessfulExit` 설정이나 종료 경로의 exit code에 문제가 있는 것이므로 보고할 것.

- [ ] **Step 5: 중복 실행 가드 확인**

```bash
open "$DERIVED/Ping.app"
sleep 3
open "$DERIVED/Ping.app"
sleep 3
pgrep -cf "Ping.app/Contents/MacOS/Ping"
```

Expected: `1`

- [ ] **Step 6: 로그인 항목 목록에 노출되는지 확인**

시스템 설정 › 일반 › 로그인 항목을 열어 "백그라운드에서 허용" 목록에 **Ping**이 (raw label이 아니라) 표시되는지 확인한다. `AssociatedBundleIdentifiers`가 동작하는지 보는 것이다.

- [ ] **Step 7: 스펙에 알려진 한계 추가**

`docs/superpowers/specs/2026-08-04-macos-autostart-keepalive-design.md`의 `## 9. 리스크와 트레이드오프` 섹션 끝에 추가:

```markdown
**수동 재실행 인스턴스는 launchd 관리 밖이다.** 사용자가 메뉴바에서 "종료"하면 launchd 잡도 멈춘다(정상 종료라 KeepAlive가 재실행하지 않는다). 그 상태에서 사용자가 Ping.app을 직접 실행하면 그 프로세스는 LaunchServices가 띄운 것이라 launchd 관리 대상이 아니고, 이후 비정상 종료돼도 되살아나지 않는다. 다음 로그인에 `RunAtLoad`로 다시 관리 하에 들어온다. 이를 즉시 교정하려면 실행 중인 인스턴스를 죽이고 launchd로 다시 띄워야 하는데, 그 부작용이 이득보다 크다고 판단해 받아들인다.
```

- [ ] **Step 8: 정리와 커밋**

```bash
pkill -f "Ping.app/Contents/MacOS/Ping" || true
git add docs/superpowers/specs/2026-08-04-macos-autostart-keepalive-design.md
git commit -m "$(cat <<'EOF'
docs(spec): record the unmanaged manual-relaunch limitation

Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>
EOF
)"
```

- [ ] **Step 9: 검증 결과 보고**

Step 2-6의 실제 출력을 그대로 보고한다. 통과한 항목과 실패한 항목을 구분해서 적을 것. 실패를 통과로 적지 말 것.

---

## 자체 리뷰 결과

**스펙 커버리지:** §4.1 plist → Task 1. §4.2 종료 경로 → Task 1(plist) + Task 8(실측). §4.3 빌드 통합 → Task 1. §4.4 정책 → Task 2. §4.5 중복 가드 → Task 4 + Task 6. §4.6 크래시 루프 → Task 3 + Task 5. §4.7 설정 UI → Task 7. §4.8 컴포넌트 경계 → Task 2-5의 파일 분리. §5 변경 파일 목록 → 전 태스크에 배분됨. §6 에러 처리 → Task 5의 `applyPolicyAtLaunch` catch + `setEnabled` throws. §7 테스트 → 각 태스크 + Task 8. 누락 없음.

**스펙과 달라진 점 1건:** 스펙 §5는 `LocalNotificationCenter.swift` 수정을 파일 목록에 넣지 않았으나, §4.6의 "로컬 알림을 띄운다"를 구현하려면 필요하다. Task 5에 포함했다.
