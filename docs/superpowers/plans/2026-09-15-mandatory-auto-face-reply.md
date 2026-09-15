# Mandatory Auto Face Reply Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make macOS automatic face replies mandatory and remove every user-facing and stored opt-out path.

**Architecture:** Keep `AutoFaceReplyPolicy` as the single eligibility decision point, but remove enablement state from its input. Preserve freshness, camera, duplicate, and loop-prevention guards unchanged. Remove the Settings binding and obsolete preference code rather than hard-coding a dead preference to true.

**Tech Stack:** Swift 6, SwiftUI, AppKit, XCTest

**Design:** `docs/superpowers/specs/2026-09-15-mandatory-auto-face-reply-design.md`

---

### Task 1: Lock the mandatory policy contract with failing tests

**Files:**
- Modify: `PingTests/AutoFaceReplyPolicyTests.swift`
- Modify: `PingTests/AutoFaceReplyContractTests.swift`

- [ ] **Step 1: Remove enablement from the policy test fixture**

Change the helper to construct contexts without `isEnabled`:

```swift
private func context(
    incomingIsAutoReply: Bool = false,
    createdAtOffset: TimeInterval? = 5,
    nowOffset: TimeInterval = 10,
    alreadyReplied: Bool = false,
    isCameraAuthorized: Bool = true,
    isCameraBusy: Bool = false
) -> AutoFaceReplyPolicy.Context {
    AutoFaceReplyPolicy.Context(
        incomingIsAutoReply: incomingIsAutoReply,
        messageCreatedAt: createdAtOffset.map { launch.addingTimeInterval($0) },
        appStartedAt: launch,
        now: launch.addingTimeInterval(nowOffset),
        alreadyReplied: alreadyReplied,
        isCameraAuthorized: isCameraAuthorized,
        isCameraBusy: isCameraBusy
    )
}
```

Delete `testSkipsWhenTheSettingIsOff`, `testDisabledSettingIsReportedAheadOfEveryOtherReason`, and the entire `AutoFaceReplyPreferenceTests` class.

- [ ] **Step 2: Replace opt-out contract assertions with absence assertions**

Update the coordinator and Settings contract tests:

```swift
func testCoordinatorDelegatesTheDecisionToThePolicyWithoutAUserPreference() throws {
    let source = try readFixture("AutoFaceReplyCoordinator.swift")

    XCTAssertTrue(source.contains("AutoFaceReplyPolicy.decide"))
    XCTAssertTrue(source.contains("incomingIsAutoReply: message.isAutoReply"))
    XCTAssertFalse(source.contains("PingAutoFaceReplyPreference"))
    XCTAssertTrue(source.contains("auto_face_reply_skipped"))
}

func testSettingsDoNotExposeAnAutoFaceReplyOptOut() throws {
    let source = try readFixture("SettingsScene.swift")

    XCTAssertFalse(source.contains("PingPreferenceKeys.autoFaceReplyOnPing"))
    XCTAssertFalse(source.contains("핑 받으면 자동으로 얼굴 회신"))
    XCTAssertFalse(source.contains("$autoFaceReplyOnPing"))
}

func testPreferencesDoNotRetainTheObsoleteAutoReplyKey() throws {
    let source = try readFixture("UserPreferences.swift")

    XCTAssertFalse(source.contains("autoFaceReplyOnPing"))
    XCTAssertFalse(source.contains("PingAutoFaceReplyPreference"))
}
```

- [ ] **Step 3: Run the focused tests and confirm the production API mismatch fails**

Run:

```bash
xcodebuild -project Ping.xcodeproj -scheme Ping -destination "platform=macOS" \
  -only-testing:PingTests/AutoFaceReplyPolicyTests \
  -only-testing:PingTests/AutoFaceReplyContractTests test
```

Expected: FAIL because production still requires `isEnabled` and still contains the preference/UI opt-out.

- [ ] **Step 4: Commit the failing contract**

```bash
git add PingTests/AutoFaceReplyPolicyTests.swift PingTests/AutoFaceReplyContractTests.swift
git commit -m "test(macos): require mandatory auto face replies"
```

### Task 2: Remove the opt-out from policy, coordinator, preferences, and Settings

**Files:**
- Modify: `Ping/Core/AutoFaceReplyPolicy.swift`
- Modify: `Ping/Capture/AutoFaceReplyCoordinator.swift`
- Modify: `Ping/Core/UserPreferences.swift`
- Modify: `Ping/UI/Setup/SettingsScene.swift`

- [ ] **Step 1: Remove the disabled policy state**

Delete `Skip.disabled`, `Context.isEnabled`, and the first enablement guard. The decision method begins with loop prevention:

```swift
static func decide(_ context: Context) -> Decision {
    guard !context.incomingIsAutoReply else { return .skip(.autoReplyMessage) }
    guard !context.alreadyReplied else { return .skip(.alreadyReplied) }
    guard let createdAt = context.messageCreatedAt else { return .skip(.missingTimestamp) }
    guard createdAt > context.appStartedAt,
          context.now.timeIntervalSince(createdAt) <= freshnessWindow else {
        return .skip(.staleMessage)
    }
    guard context.isCameraAuthorized else { return .skip(.cameraUnavailable) }
    guard !context.isCameraBusy else { return .skip(.cameraBusy) }
    return .record
}
```

- [ ] **Step 2: Remove the preference argument from the coordinator**

Construct `AutoFaceReplyPolicy.Context` without this line:

```swift
isEnabled: PingAutoFaceReplyPreference.isEnabled,
```

- [ ] **Step 3: Delete obsolete preference storage code**

Delete this key:

```swift
static let autoFaceReplyOnPing = "ping.autoReply.faceOnPing"
```

Delete the complete `PingAutoFaceReplyPreference` enum. Do not migrate or overwrite old defaults; an unused legacy value cannot affect behavior.

- [ ] **Step 4: Remove the Settings row cleanly**

Delete the `@AppStorage(PingPreferenceKeys.autoFaceReplyOnPing)` property, its `autoFaceReplyOnPing` value, the complete `settingRow` titled `핑 받으면 자동으로 얼굴 회신`, and the divider immediately following that row. Keep exactly one divider between `받은 영상 바로 재생` and `알림 소리`.

- [ ] **Step 5: Run focused tests**

Run the Task 1 command again.

Expected: PASS.

- [ ] **Step 6: Commit the implementation**

```bash
git add Ping/Core/AutoFaceReplyPolicy.swift Ping/Capture/AutoFaceReplyCoordinator.swift \
  Ping/Core/UserPreferences.swift Ping/UI/Setup/SettingsScene.swift
git commit -m "feat(macos): make auto face replies mandatory"
```

### Task 3: Align product documentation and verify

**Files:**
- Modify: `PING_PROJECT_SPECIFICATION.md`

- [ ] **Step 1: Update the product contract**

In `자동 얼굴 회신 (macOS)`, replace the opt-out bullet with:

```markdown
- 모든 macOS 사용자에게 필수로 적용되며 설정에서 끌 수 없다.
```

Remove `설정 꺼짐` from the skip list. Replace the privacy statement with:

```markdown
- 자동 얼굴 회신은 모든 macOS 사용자에게 필수로 적용된다. 자동 회신에는 다시 회신하지 않고, 오래된 핑과 카메라를 사용할 수 없는 상황은 건너뛰며, 녹화 중에는 수신자 화면에 인디케이터가 표시된다.
```

- [ ] **Step 2: Confirm no live opt-out references remain**

Run:

```bash
rg -n "autoFaceReplyOnPing|PingAutoFaceReplyPreference|설정 꺼짐|켜고 끈다" Ping PingTests PING_PROJECT_SPECIFICATION.md
```

Expected: no matches.

- [ ] **Step 3: Run the complete test suite and build**

```bash
xcodebuild -project Ping.xcodeproj -scheme Ping -destination "platform=macOS" test
xcodebuild -project Ping.xcodeproj -scheme Ping -configuration Debug \
  -destination "platform=macOS" build
```

Expected: `** TEST SUCCEEDED **` and `** BUILD SUCCEEDED **`.

- [ ] **Step 4: Commit documentation**

```bash
git add PING_PROJECT_SPECIFICATION.md
git commit -m "docs(macos): document mandatory auto face replies"
```
