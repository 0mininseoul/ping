# macOS 자동 시작 + 자동 복구(KeepAlive) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Ping.app이 로그인 시 자동으로 켜지고, macOS `cache_delete`의 강제 종료나 크래시로 꺼져도 launchd가 수 초 안에 되살리게 한다.

**Architecture:** 앱 번들 안(`Contents/Library/LaunchAgents/`)에 LaunchAgent plist를 넣고 `SMAppService.agent(plistName:)`로 등록해 프로세스 수명을 launchd에 맡긴다. `KeepAlive = { SuccessfulExit: false }`가 비정상 종료만 골라 재실행하므로 사용자가 메뉴바에서 "종료"한 경우는 되살아나지 않는다. `SMAppService`는 단위 테스트가 불가능하므로 "무엇을 등록/해제할지" 판단만 순수 함수(`AutoStartPolicy`)로 떼어내 검증하고, 실제 호출은 `AutoStartController` 한 곳에 모은다. 둘은 파일 하나(`Ping/Core/AutoStart.swift`)에 같이 산다.

**범위(YAGNI):** 최소 변경으로 간다. 신규 Swift 파일 1개, 수정 3개. 설계 문서 §4.5(중복 실행 가드)와 §4.6(크래시 루프 차단)은 **구현하지 않는다** — 전자는 LaunchServices가 이미 같은 번들의 두 번째 인스턴스를 막고, 후자는 `ThrottleInterval 30`과 시스템 설정 › 로그인 항목이라는 탈출구가 이미 있는 가상 시나리오 대비였다. 실제로 문제가 관측되면 그때 추가한다.

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
| `Ping/Core/AutoStart.swift` | 신규 Swift 파일. `AutoStartStatus`·`AutoStartAction`·`AutoStartPolicy`(순수 판정) + `AutoStartController`(`SMAppService` 호출) |
| `Ping/Core/UserPreferences.swift` | UserDefaults 키 1개 추가 |
| `Ping/AppDelegate.swift` | 기동 시 정책 적용 1줄 |
| `Ping/UI/Setup/SettingsScene.swift` | 토글 배선만 controller로 교체. 문구 불변 |

---

## Task 1: LaunchAgent plist와 번들 통합

plist를 만들고 앱 번들의 `Contents/Library/LaunchAgents/`에 서명 포함된 상태로 들어가게 한다. 이 태스크는 코드를 부르지 않는다 — 파일이 올바른 자리에 올바른 내용으로 들어갔는지만 보장한다.

**Files:**
- Create: `Resources/LaunchAgents/com.youngminpark.ping.Ping.keepalive.plist`
- Modify: `project.yml` (Ping 타깃 `sources`에 copyFiles 빌드 페이즈 추가 / PingTests `Copy Contract Test Fixtures`에 fixture 추가)
- Test: `PingTests/AutoStartAgentPlistTests.swift`

**Interfaces:**
- Consumes: 없음 (첫 태스크)
- Produces: 번들 경로 `Contents/Library/LaunchAgents/com.youngminpark.ping.Ping.keepalive.plist`, 잡 Label `com.youngminpark.ping.Ping.keepalive`. Task 2의 `AutoStartController.agentPlistName`이 이 파일명을 참조한다.

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

## Task 2: AutoStart.swift — 등록 정책과 SMAppService 어댑터

`SMAppService` 호출은 단위 테스트가 불가능하다(시스템 등록을 건드린다). 그래서 "무엇을 해야 하는가"를 정하는 순수 함수만 떼어내 전수 테스트하고, 실제 호출은 얇은 컨트롤러에 둔다. 둘 다 파일 하나에 산다.

**Files:**
- Create: `Ping/Core/AutoStart.swift`
- Modify: `Ping/Core/UserPreferences.swift` (`PingPreferenceKeys`에 키 1개 추가)
- Test: `PingTests/AutoStartPolicyTests.swift`

**Interfaces:**
- Consumes: Task 1이 번들에 넣은 plist 파일명 `com.youngminpark.ping.Ping.keepalive.plist`
- Produces:
  - `enum AutoStartStatus: Equatable { case enabled, requiresApproval, notRegistered, notFound, unknown }` + `var isRegistered: Bool`
  - `enum AutoStartAction: Equatable { case none, registerAgent, unregisterAgent, migrateFromMainApp }`
  - `enum AutoStartPolicy { static func action(userChoice: Bool?, agentStatus: AutoStartStatus, mainAppStatus: AutoStartStatus) -> AutoStartAction }`
  - `@MainActor final class AutoStartController` — `static let shared`, `static let agentPlistName`, `init(defaults: UserDefaults = .standard)`, `var userChoice: Bool?`, `var status: AutoStartStatus`, `static func map(_:) -> AutoStartStatus`, `func setEnabled(_ enabled: Bool) throws`, `func applyPolicyAtLaunch()`
  - `PingPreferenceKeys.autostartUserChoice` = `"ping.autostart.userChoice"`
  - Task 3의 `AppDelegate`와 `SettingsScene`이 쓴다.

- [ ] **Step 1: 실패하는 테스트 작성**

`PingTests/AutoStartPolicyTests.swift`:

```swift
import ServiceManagement
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

    // MARK: 컨트롤러

    @MainActor
    func testUserChoiceRoundTripsAndDistinguishesFalseFromUnset() {
        let suiteName = "AutoStartPolicyTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let controller = AutoStartController(defaults: defaults)
        XCTAssertNil(controller.userChoice)

        controller.userChoice = true
        XCTAssertEqual(controller.userChoice, true)

        // bool(forKey:)로 읽으면 false와 미설정이 뭉개져 사용자가 끈 상태가 매 기동마다 다시 켜진다.
        controller.userChoice = false
        XCTAssertEqual(controller.userChoice, false)
        XCTAssertNotNil(controller.userChoice)
    }

    @MainActor
    func testStatusMappingCoversEveryServiceManagementCase() {
        XCTAssertEqual(AutoStartController.map(.enabled), .enabled)
        XCTAssertEqual(AutoStartController.map(.requiresApproval), .requiresApproval)
        XCTAssertEqual(AutoStartController.map(.notRegistered), .notRegistered)
        XCTAssertEqual(AutoStartController.map(.notFound), .notFound)
    }

    @MainActor
    func testAgentPlistNameMatchesBundledFile() {
        XCTAssertEqual(
            AutoStartController.agentPlistName,
            "com.youngminpark.ping.Ping.keepalive.plist"
        )
    }

    func testPreferenceKeyIsStable() {
        XCTAssertEqual(PingPreferenceKeys.autostartUserChoice, "ping.autostart.userChoice")
    }
}
```

- [ ] **Step 2: 테스트가 실패하는지 확인**

```bash
xcodebuild -project Ping.xcodeproj -scheme Ping -destination "platform=macOS" test \
  -only-testing:PingTests/AutoStartPolicyTests
```
Expected: 컴파일 실패 — `AutoStartStatus` / `AutoStartAction` / `AutoStartPolicy` / `AutoStartController` / `PingPreferenceKeys.autostartUserChoice` 전부 미정의.

- [ ] **Step 3: UserDefaults 키 추가**

`Ping/Core/UserPreferences.swift`의 `PingPreferenceKeys`에서 `appearanceMode` 줄 아래에 추가:

```swift
    static let autostartUserChoice = "ping.autostart.userChoice"
```

- [ ] **Step 4: 구현**

`Ping/Core/AutoStart.swift`:

```swift
import Foundation
import OSLog
import ServiceManagement

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

/// 자동 시작 등록 상태를 관리한다. `SMAppService`를 호출하는 곳은 이 클래스 하나뿐이다.
@MainActor
final class AutoStartController {
    static let shared = AutoStartController()
    static let agentPlistName = "com.youngminpark.ping.Ping.keepalive.plist"

    private let defaults: UserDefaults
    private let logger = Logger(subsystem: "com.youngminpark.ping.Ping", category: "autostart")

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
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
}
```

- [ ] **Step 5: 테스트 통과 확인**

```bash
xcodegen generate
xcodebuild -project Ping.xcodeproj -scheme Ping -destination "platform=macOS" test \
  -only-testing:PingTests/AutoStartPolicyTests
```
Expected: PASS (12개 테스트)

- [ ] **Step 6: 커밋**

```bash
git add Ping/Core/AutoStart.swift Ping/Core/UserPreferences.swift PingTests/AutoStartPolicyTests.swift Ping.xcodeproj
git commit -m "$(cat <<'EOF'
feat(autostart): add auto-start policy and SMAppService controller

Default-on for first run, one-shot migration off the legacy login item,
self-healing re-register when the bundle moves. A stored userChoice of
false is never reversed.

Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>
EOF
)"
```

---

## Task 3: 기동 훅과 설정 토글 배선

앱이 뜰 때 정책을 적용하고, 설정 토글이 구 로그인 항목 대신 KeepAlive agent를 조작하게 한다. **설정 화면의 문구와 레이아웃은 한 글자도 바꾸지 않는다.**

**Files:**
- Modify: `Ping/AppDelegate.swift` (`applicationDidFinishLaunching`의 `if !ProcessInfo.processInfo.isRunningUnitTests {` 블록)
- Modify: `Ping/UI/Setup/SettingsScene.swift` (3행 import, `updateAutoLaunch`, `isAutoLaunchEnabled`, `autoLaunchStatusText`)
- Test: `PingTests/AutoStartSettingsWiringTests.swift`

**Interfaces:**
- Consumes: `AutoStartController` (Task 2)
- Produces: 없음 (통합 지점)

`SettingsScene.swift`는 이미 `project.yml`의 `Copy Contract Test Fixtures`에 등록돼 있으므로 fixture 추가 작업이 필요 없다.

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

- [ ] **Step 3: 기동 훅 추가**

`Ping/AppDelegate.swift`의 `applicationDidFinishLaunching` 안에서 `if !ProcessInfo.processInfo.isRunningUnitTests {` 바로 다음 줄에 한 줄을 추가한다. `showsOnboardingForQA` 조기 반환보다 **앞**이어야 QA 프리뷰 모드에서도 정책이 적용된다:

```swift
        if !ProcessInfo.processInfo.isRunningUnitTests {
            AutoStartController.shared.applyPolicyAtLaunch()

            if showsOnboardingForQA {
```

나머지 줄은 건드리지 않는다.

- [ ] **Step 4: `updateAutoLaunch` 교체**

`Ping/UI/Setup/SettingsScene.swift`의 `updateAutoLaunch(_:)`를 다음으로 교체:

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

- [ ] **Step 5: 상태 조회 두 개 교체**

같은 파일의 `isAutoLaunchEnabled()`와 `autoLaunchStatusText()`를 다음으로 교체:

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

- [ ] **Step 6: 쓰이지 않는 import 제거**

`SettingsScene.swift` 3행의 `import ServiceManagement`를 삭제한다. 이 파일에서 `SMAppService`를 더 이상 참조하지 않는다.

- [ ] **Step 7: 테스트 통과 확인**

```bash
xcodegen generate
xcodebuild -project Ping.xcodeproj -scheme Ping -destination "platform=macOS" test \
  -only-testing:PingTests/AutoStartSettingsWiringTests
```
Expected: PASS (2개 테스트)

**`@State` 초기화에서 `@MainActor` 격리 오류가 나면**: `@State private var autoLaunchEnabled = Self.isAutoLaunchEnabled()` / `@State private var autoLaunchStatusText = Self.autoLaunchStatusText()`를 `= false` / `= ""`로 바꾸고, 뷰 `body`의 최상위 컨테이너에 `.onAppear { refreshAutoLaunchStatus() }`를 붙인다. 표시 문구는 그대로 유지된다.

- [ ] **Step 8: 전체 테스트로 회귀 확인**

```bash
xcodebuild -project Ping.xcodeproj -scheme Ping -destination "platform=macOS" test
```
Expected: 전부 PASS. 기존 테스트가 깨지면 진행하지 말고 원인을 보고할 것.

- [ ] **Step 9: 커밋**

```bash
git add Ping/AppDelegate.swift Ping/UI/Setup/SettingsScene.swift PingTests/AutoStartSettingsWiringTests.swift Ping.xcodeproj
git commit -m "$(cat <<'EOF'
feat(autostart): apply the policy at launch and rewire the settings toggle

Registering mainApp alongside the agent would launch Ping twice at login.
Visible settings copy and layout are unchanged — only the wiring moved.

Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>
EOF
)"
```

---

## Task 4: 실기기 검증 (컨트롤러가 직접 수행)

`SMAppService` 등록과 launchd 재실행은 단위 테스트로 검증할 수 없다. **이 태스크는 서브에이전트에 위임하지 않는다** — `pkill -f "Ping.app/Contents/MacOS/Ping"`가 사용자의 실제 `/Applications/Ping.app`까지 죽이고, DerivedData 빌드를 가리키는 launchd 잡을 등록할 수 있기 때문이다. 사용자 승인 후 컨트롤러가 직접 실행한다.

- [ ] **Step 1: 사용자에게 확인받기** — 검증 중 실행 중인 Ping이 종료되고, 임시로 DerivedData 빌드가 로그인 항목에 등록된다는 점을 알린다. 검증 후 원복 방법(Step 6)도 함께 제시한다.

- [ ] **Step 2: 빌드와 서명 확인**

```bash
xcodegen generate
xcodebuild -project Ping.xcodeproj -scheme Ping -configuration Debug -destination "platform=macOS" build
DERIVED=$(xcodebuild -project Ping.xcodeproj -scheme Ping -showBuildSettings \
          | grep -m1 BUILT_PRODUCTS_DIR | awk '{print $3}')
ls -l "$DERIVED/Ping.app/Contents/Library/LaunchAgents/"
codesign --verify --deep --strict "$DERIVED/Ping.app" && echo "SIGNATURE OK"
```

- [ ] **Step 3: `BundleProgram` 해석 검증 (가장 불확실한 지점)**

```bash
osascript -e 'tell application "Ping" to quit' || true
open "$DERIVED/Ping.app"
sleep 5
launchctl print "gui/$(id -u)/com.youngminpark.ping.Ping.keepalive"
```

Expected: 잡이 출력되고 program 경로가 실제 앱 실행 파일을 가리키며 `state = running`.

**실패 시**: `BundleProgram`이 기대대로 해석되지 않은 것이다. 폴백은 `ProgramArguments` 절대 경로 + "앱은 /Applications에 있어야 함" 제약이지만, 임의로 적용하지 말고 `launchctl print` 출력과 함께 사용자에게 보고할 것.

- [ ] **Step 4: 비정상 종료 → 재실행 확인**

```bash
PID=$(pgrep -f "Ping.app/Contents/MacOS/Ping"); echo "before: $PID"; kill -9 "$PID"; sleep 40
echo "after: $(pgrep -f 'Ping.app/Contents/MacOS/Ping')"
```
Expected: 40초 안에 **다른 pid**로 살아 있다 (`ThrottleInterval 30` 때문에 최대 30초).

- [ ] **Step 5: 정상 종료 → 재실행 안 되는지 확인**

```bash
osascript -e 'tell application "Ping" to quit'; sleep 45
pgrep -f "Ping.app/Contents/MacOS/Ping" || echo "STAYED DOWN (correct)"
```
Expected: `STAYED DOWN (correct)`. 되살아나면 `KeepAlive.SuccessfulExit` 설정이나 종료 경로의 exit code 문제이므로 보고할 것.

- [ ] **Step 6: 검증용 등록 원복**

DerivedData 빌드로 등록된 잡을 지우고 사용자의 실제 앱 상태로 되돌린다:

```bash
pkill -f "Ping.app/Contents/MacOS/Ping" || true
launchctl bootout "gui/$(id -u)/com.youngminpark.ping.Ping.keepalive" 2>/dev/null || true
defaults delete com.youngminpark.ping.Ping ping.autostart.userChoice 2>/dev/null || true
open -a /Applications/Ping.app
```

시스템 설정 › 일반 › 로그인 항목에 DerivedData 빌드를 가리키는 잔여 항목이 없는지 눈으로 확인한다.

- [ ] **Step 7: 결과 보고** — Step 2-5의 실제 출력을 그대로 보고한다. 통과 항목과 실패 항목을 구분해 적고, 실패를 통과로 적지 않는다.

---

## 자체 리뷰 결과

**스펙 커버리지:** 설계 문서 §4.1 plist → Task 1. §4.2 종료 경로 → Task 1(plist) + Task 4(실측). §4.3 빌드 통합 → Task 1. §4.4 정책 → Task 2. §4.7 설정 UI → Task 3. §6 에러 처리 → Task 2의 `applyPolicyAtLaunch` catch + `setEnabled` throws. §7 테스트 → 각 태스크 + Task 4.

**의도적으로 구현하지 않는 스펙 항목 2건** (YAGNI, 플랜 헤더의 범위 절 참조):
- §4.5 중복 실행 가드 — LaunchServices가 같은 번들의 두 번째 인스턴스를 이미 막는다.
- §4.6 크래시 루프 차단 — `ThrottleInterval 30`과 시스템 설정 › 로그인 항목이라는 탈출구가 이미 있다.

이에 따라 스펙 §5의 파일 목록 중 `LaunchLedger.swift` / `SingleInstanceGuard.swift` / `LocalNotificationCenter.swift` 수정은 발생하지 않고, `AutoStartPolicy.swift`와 `AutoStartController.swift`는 `AutoStart.swift` 한 파일로 합쳐진다. Task 4 완료 후 스펙에 이 축소를 기록한다.
