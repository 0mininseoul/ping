# macOS KeepAlive Ownership Repair Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Ensure the sole running Ping process is owned by the registered launchd agent so abnormal termination is automatically recovered, while normal Quit remains final for the current login session.

**Architecture:** Detect whether the current process was launched by the KeepAlive agent using its exact `XPC_SERVICE_NAME`. Make a managed instance win duplicate arbitration, and make an unmanaged launch refresh the ServiceManagement registration asynchronously so launchd starts a current managed instance. Preserve `KeepAlive.SuccessfulExit = false` for normal-Quit semantics.

**Tech Stack:** Swift 6, AppKit, ServiceManagement, XCTest, XcodeGen

**Design:** `docs/superpowers/specs/2026-09-15-macos-keepalive-ownership-design.md`

---

### Task 1: Specify launch origin and process ownership with failing tests

**Files:**
- Modify: `PingTests/AutoStartLaunchGuardTests.swift`

- [ ] **Step 1: Replace boolean duplicate tests with ownership actions**

Add tests for the three decisions:

```swift
func testProceedsWhenNoOtherInstanceExists() {
    XCTAssertEqual(
        SingleInstanceGuard.action(runningPIDs: [42], currentPID: 42, isAgentManaged: false),
        .proceed
    )
}

func testUnmanagedDuplicateYieldsToExistingInstance() {
    XCTAssertEqual(
        SingleInstanceGuard.action(runningPIDs: [17, 42], currentPID: 42, isAgentManaged: false),
        .yield
    )
}

func testManagedDuplicateReplacesExistingInstance() {
    XCTAssertEqual(
        SingleInstanceGuard.action(runningPIDs: [17, 42], currentPID: 42, isAgentManaged: true),
        .replaceExisting([17])
    )
}
```

Keep the unknown-bundle locator test.

- [ ] **Step 2: Add exact launch-origin tests**

```swift
func testRecognizesOnlyTheKeepAliveServiceNameAsManaged() {
    XCTAssertTrue(PingLaunchOrigin.isAgentManaged(environment: [
        "XPC_SERVICE_NAME": "com.youngminpark.ping.Ping.keepalive"
    ]))
    XCTAssertFalse(PingLaunchOrigin.isAgentManaged(environment: [
        "XPC_SERVICE_NAME": "application.com.youngminpark.ping.Ping.random"
    ]))
    XCTAssertFalse(PingLaunchOrigin.isAgentManaged(environment: [:]))
}
```

- [ ] **Step 3: Update source-wiring assertions**

Assert that `AppDelegate.swift` switches on `SingleInstanceGuard.action`, retains `exit(0)` for `.yield`, and calls `NSRunningApplication(processIdentifier:)?.terminate()` for `.replaceExisting`.

- [ ] **Step 4: Run and confirm failure**

```bash
xcodebuild -project Ping.xcodeproj -scheme Ping -destination "platform=macOS" \
  -only-testing:PingTests/AutoStartLaunchGuardTests test
```

Expected: FAIL because the action and launch-origin APIs do not exist.

- [ ] **Step 5: Commit the failing tests**

```bash
git add PingTests/AutoStartLaunchGuardTests.swift
git commit -m "test(autostart): require launchd process ownership"
```

### Task 2: Implement deterministic process ownership

**Files:**
- Modify: `Ping/Core/AutoStart.swift`
- Modify: `Ping/AppDelegate.swift`

- [ ] **Step 1: Add launch-origin detection and ownership actions**

Add to `AutoStart.swift`:

```swift
enum PingLaunchOrigin {
    static let agentServiceName = "com.youngminpark.ping.Ping.keepalive"

    static func isAgentManaged(environment: [String: String] = ProcessInfo.processInfo.environment) -> Bool {
        environment["XPC_SERVICE_NAME"] == agentServiceName
    }
}

enum SingleInstanceAction: Equatable {
    case proceed
    case yield
    case replaceExisting([pid_t])
}
```

Replace `shouldYield` with:

```swift
static func action(
    runningPIDs: [pid_t],
    currentPID: pid_t,
    isAgentManaged: Bool
) -> SingleInstanceAction {
    let others = runningPIDs.filter { $0 != currentPID }
    guard !others.isEmpty else { return .proceed }
    return isAgentManaged ? .replaceExisting(others) : .yield
}
```

- [ ] **Step 2: Wire ownership into AppDelegate before setup**

Store launch origin once:

```swift
private let isAgentManagedProcess = PingLaunchOrigin.isAgentManaged()
```

In `applicationWillFinishLaunching`, switch on the ownership action. `.yield` calls `exit(0)`. `.replaceExisting(let pids)` resolves each PID with `NSRunningApplication(processIdentifier:)` and calls `terminate()`. `.proceed` does nothing. Then apply the accessory activation policy.

```swift
func applicationWillFinishLaunching(_ notification: Notification) {
    if !ProcessInfo.processInfo.isRunningUnitTests {
        let currentPID = ProcessInfo.processInfo.processIdentifier
        let runningPIDs = SingleInstanceGuard.runningPIDs(
            forBundleIdentifier: Bundle.main.bundleIdentifier ?? ""
        )
        switch SingleInstanceGuard.action(
            runningPIDs: runningPIDs,
            currentPID: currentPID,
            isAgentManaged: isAgentManagedProcess
        ) {
        case .proceed:
            break
        case .yield:
            exit(0)
        case .replaceExisting(let pids):
            for pid in pids {
                NSRunningApplication(processIdentifier: pid)?.terminate()
            }
        }
    }

    enforceAccessoryActivationPolicy()
}
```

- [ ] **Step 3: Run focused tests**

Run the Task 1 test command.

Expected: PASS.

- [ ] **Step 4: Commit ownership behavior**

```bash
git add Ping/Core/AutoStart.swift Ping/AppDelegate.swift
git commit -m "fix(autostart): let launchd own the running app"
```

### Task 3: Specify and implement safe ServiceManagement re-registration

**Files:**
- Modify: `PingTests/AutoStartPolicyTests.swift`
- Modify: `Ping/Core/AutoStart.swift`
- Modify: `Ping/AppDelegate.swift`

- [ ] **Step 1: Add failing policy tests for managed state**

Update every `AutoStartPolicy.action` call with `isAgentManaged: true` for existing behavior. Add:

```swift
func testEnabledUnmanagedLaunchRefreshesRegisteredAgent() {
    XCTAssertEqual(
        AutoStartPolicy.action(
            userChoice: true,
            agentStatus: .enabled,
            mainAppStatus: .notRegistered,
            isAgentManaged: false
        ),
        .reregisterAgent
    )
}

func testEnabledManagedLaunchDoesNotRefreshAgent() {
    XCTAssertEqual(
        AutoStartPolicy.action(
            userChoice: true,
            agentStatus: .enabled,
            mainAppStatus: .notRegistered,
            isAgentManaged: true
        ),
        .none
    )
}
```

- [ ] **Step 2: Run the policy tests and confirm failure**

```bash
xcodebuild -project Ping.xcodeproj -scheme Ping -destination "platform=macOS" \
  -only-testing:PingTests/AutoStartPolicyTests test
```

Expected: FAIL because `.reregisterAgent` and `isAgentManaged` do not exist.

- [ ] **Step 3: Extend the pure policy**

Add `.reregisterAgent` to `AutoStartAction`, add `isAgentManaged` to `AutoStartPolicy.action`, and reconcile enabled state as follows:

```swift
private static func reconcileEnabled(
    _ agentStatus: AutoStartStatus,
    isAgentManaged: Bool
) -> AutoStartAction {
    switch agentStatus {
    case .enabled:
        return isAgentManaged ? .none : .reregisterAgent
    case .requiresApproval, .unknown:
        return .none
    case .notRegistered, .notFound:
        return .registerAgent
    }
}
```

- [ ] **Step 4: Add asynchronous unregister then register**

Make launch reconciliation asynchronous and implement:

```swift
private func reregisterAgent() async throws {
    let service = agent
    try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
        service.unregister { error in
            if let error {
                continuation.resume(throwing: error)
            } else {
                continuation.resume()
            }
        }
    }
    try service.register()
}
```

Handle `.reregisterAgent` in `applyPolicyAtLaunch(isAgentManaged:)` by awaiting this helper. Pass `isAgentManaged` into the pure policy.

- [ ] **Step 5: Start async reconciliation from AppDelegate**

Replace the synchronous call with:

```swift
Task { @MainActor in
    await AutoStartController.shared.applyPolicyAtLaunch(
        isAgentManaged: isAgentManagedProcess
    )
}
```

- [ ] **Step 6: Run both focused AutoStart suites**

```bash
xcodebuild -project Ping.xcodeproj -scheme Ping -destination "platform=macOS" \
  -only-testing:PingTests/AutoStartPolicyTests \
  -only-testing:PingTests/AutoStartLaunchGuardTests test
```

Expected: PASS.

- [ ] **Step 7: Commit re-registration**

```bash
git add PingTests/AutoStartPolicyTests.swift Ping/Core/AutoStart.swift Ping/AppDelegate.swift
git commit -m "fix(autostart): refresh keepalive registration after relaunch"
```

### Task 4: Update lifecycle documentation and run full verification

**Files:**
- Modify: `docs/superpowers/specs/2026-08-04-macos-autostart-keepalive-design.md`
- Modify: `PING_PROJECT_SPECIFICATION.md`
- Modify: `README.md`

- [ ] **Step 1: Supersede the accepted ownership gaps**

Add a dated note to the 2026-08-04 design stating that its `등록한 세션`, `Sparkle 업데이트 후`, and `수동 재실행` unprotected trade-offs are superseded by `2026-09-15-macos-keepalive-ownership-design.md`.

```markdown
> 2026-09-15 교정: §9에서 수용했던 등록 직후·Sparkle 업데이트 후·수동 재실행 세션의
> launchd 감시 공백은 실제 장애를 일으켰다. 해당 트레이드오프는
> `2026-09-15-macos-keepalive-ownership-design.md`의 소유권 이관과 재등록 설계로 대체한다.
```

- [ ] **Step 2: Align product and release documentation**

Document that abnormal termination is followed by launchd recovery, normal user Quit remains stopped for the session, and manual/Sparkle relaunches refresh registration and transfer ownership. Do not claim that resource-pressure termination itself is prevented.

Use this product-spec wording:

```markdown
- 실행 중인 Ping은 launchd KeepAlive agent가 소유한다. 잠자기·메모리 압박·디스크 압박·크래시로 비정상 종료되면 자동 재실행하고, 사용자가 메뉴에서 종료하면 현재 로그인 세션에서는 재실행하지 않는다.
- 수동 실행과 Sparkle 업데이트 후 재실행은 KeepAlive 등록을 현재 빌드로 갱신하고 launchd 관리 프로세스로 소유권을 넘긴다.
```

- [ ] **Step 3: Run source checks**

```bash
rg -n "reregisterAgent|isAgentManaged|replaceExisting|XPC_SERVICE_NAME" Ping PingTests
git diff --check
```

Expected: policy, controller, lifecycle wiring, and tests all contain the new contract; `git diff --check` reports no errors.

- [ ] **Step 4: Run full tests and build**

```bash
xcodebuild -project Ping.xcodeproj -scheme Ping -destination "platform=macOS" test
xcodebuild -project Ping.xcodeproj -scheme Ping -configuration Debug \
  -destination "platform=macOS" build
```

Expected: `** TEST SUCCEEDED **` and `** BUILD SUCCEEDED **`.

- [ ] **Step 5: Commit documentation**

```bash
git add docs/superpowers/specs/2026-08-04-macos-autostart-keepalive-design.md \
  PING_PROJECT_SPECIFICATION.md README.md
git commit -m "docs(autostart): document managed keepalive ownership"
```

### Task 5: Installed-app verification handoff

**Files:**
- No source changes

- [ ] **Step 1: Report automated verification separately from installed-app verification**

Record that Debug build and XCTest validate policy and wiring only. Do not claim ServiceManagement runtime success until a Developer ID signed build is installed and the destructive PID termination smoke test is explicitly run.

- [ ] **Step 2: Provide the exact signed-build smoke commands without running them automatically**

```bash
launchctl print "gui/$(id -u)/com.youngminpark.ping.Ping.keepalive"
pgrep -x Ping
```

For an explicitly authorized smoke test, compare the sole PID with launchctl, terminate that exact managed PID, wait no longer than 30 seconds, confirm a new PID, then quit through the Ping menu and confirm `last exit code = 0` with no restart.
