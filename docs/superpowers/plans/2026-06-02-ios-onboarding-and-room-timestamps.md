# iOS Onboarding and Room Timestamps Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make the first-run iPhone app clearly explain that Ping is a Mac desktop companion, give users practical ways to get `https://0minping.vercel.app` onto their Mac, and add iMessage-style timestamp reveal in mobile room threads.

**Architecture:** Keep pairing as QR session handoff from the desktop app. Add a small shared product-link constant in `PingKit`, extract the unpaired iOS screen into a focused install/scan guide view, move push permission prompting until after pairing, and mirror the macOS `RoomTimelineView` timestamp-reveal model inside `PingMobile/ThreadView.swift`.

**Tech Stack:** Swift 6, SwiftUI iOS 17, PingKit Swift Package, UIKit `UIPasteboard`, SwiftUI `ShareLink`/`Link`, XCTest source contract tests, XcodeGen-managed Xcode project.

---

## Design Guardrail

The iOS UI must stay within the existing Apple design system already used by `PingMobile`: native SwiftUI controls, SF Symbols, system typography, `Color(uiColor:)` semantic backgrounds, grouped/list-like hierarchy, and standard button styles. Do not introduce a marketing-page look, custom gradients, decorative illustration, custom typography, or non-native visual language.

## Current Review Summary

- `PingMobile/ContentView.swift` currently shows a minimal unpaired screen with only "Mac과 연결하기", one sentence about Settings > Devices, and a "Mac QR 스캔" button. A new user has no visible install URL and no clear explanation that this is a desktop companion.
- `PingMobile/AppDelegate.swift` requests notification permission during launch before pairing context exists. That can interrupt the first-run explanation.
- `Ping/UI/Setup/DevicePairingView.swift` already displays the desktop QR in Settings > Devices. The mobile work should not change the QR payload contract.
- `web/src/routes.tsx` and live `https://0minping.vercel.app` already provide the desktop download landing page. On iPhone, the best UX is not direct DMG download; it is copy/share/open guidance so the user can move the URL to their Mac.
- macOS timestamp reveal lives in `Ping/UI/History/RoomTimelineView.swift`: one shared negative `revealOffset`, `timestampWidth`, `timestampGap`, horizontal-dominant drag/scroll handling, `ZStack(alignment: .trailing)`, timestamp label behind the row, row content offset left, and quick reset.

## UX Decision

Recommended approach: a native setup checklist screen, not a separate wizard or landing-page style hero.

The first screen should say: "Ping은 Mac용 Ping의 iPhone companion입니다." Then show three steps:

1. Mac에서 `0minping.vercel.app` 열기
2. Ping 설치 후 Settings > Devices에서 QR 표시
3. 이 iPhone으로 QR 스캔

Actions:

- Primary utility: "Mac 설치 링크 복사" copies `https://0minping.vercel.app`.
- Secondary utility: "Mac으로 공유" uses the iOS share sheet so users can AirDrop, Messages, Notes, or Universal Clipboard.
- Secondary utility: "Safari에서 보기" opens the landing page on the phone for inspection, not as the main install path.
- Pairing action: "설치 끝났어요, QR 스캔" starts the existing scanner.
- Keep "앱 기능 미리보기" at the bottom for App Review.

Do not encode the install URL as a QR shown on iPhone. The user needs the URL on a Mac; the iOS share sheet and pasteboard are more practical than asking the Mac to scan the phone.

---

### Task 1: Shared Desktop Install Link

**Files:**
- Create: `PingKit/Sources/PingKit/PingProductLinks.swift`
- Modify: `PingKit/Tests/PingKitTests/PingKitTests.swift`

- [ ] **Step 1: Add failing PingKit tests for the canonical install URL**

Append this suite to `PingKit/Tests/PingKitTests/PingKitTests.swift`:

```swift
@Suite struct PingProductLinksTests {
    @Test func desktopInstallPageIsCanonicalLandingPage() throws {
        #expect(PingProductLinks.desktopInstallPage.absoluteString == "https://0minping.vercel.app")
        #expect(PingProductLinks.desktopInstallPageText == "0minping.vercel.app")
    }
}
```

- [ ] **Step 2: Run the failing package test**

Run:

```bash
swift test --package-path PingKit --filter PingProductLinksTests
```

Expected: FAIL because `PingProductLinks` does not exist.

- [ ] **Step 3: Add the shared constant**

Create `PingKit/Sources/PingKit/PingProductLinks.swift`:

```swift
import Foundation

public enum PingProductLinks {
    public static let desktopInstallPage = URL(string: "https://0minping.vercel.app")!
    public static let desktopInstallPageText = "0minping.vercel.app"
}
```

- [ ] **Step 4: Run the package test again**

Run:

```bash
swift test --package-path PingKit --filter PingProductLinksTests
```

Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add PingKit/Sources/PingKit/PingProductLinks.swift PingKit/Tests/PingKitTests/PingKitTests.swift
git commit -m "feat(ios): add shared desktop install link"
```

---

### Task 2: First-Run iOS Companion Onboarding

**Files:**
- Create: `PingMobile/DesktopInstallGuideView.swift`
- Modify: `PingMobile/ContentView.swift`
- Create: `PingTests/PingMobileOnboardingContractTests.swift`

- [ ] **Step 1: Add source contract tests for install guidance**

Create `PingTests/PingMobileOnboardingContractTests.swift`:

```swift
import XCTest

final class PingMobileOnboardingContractTests: XCTestCase {
    func testUnpairedScreenExplainsCompanionRoleAndDesktopInstallURL() throws {
        let source = try readProjectSource("PingMobile/DesktopInstallGuideView.swift")

        XCTAssertTrue(source.contains("Mac용 Ping의 iPhone companion"))
        XCTAssertTrue(source.contains("PingProductLinks.desktopInstallPage"))
        XCTAssertTrue(source.contains("PingProductLinks.desktopInstallPageText"))
        XCTAssertTrue(source.contains("Mac 설치 링크 복사"))
        XCTAssertTrue(source.contains("Mac으로 공유"))
        XCTAssertTrue(source.contains("Safari에서 보기"))
        XCTAssertTrue(source.contains("설치 끝났어요, QR 스캔"))
        XCTAssertTrue(source.contains("UIPasteboard.general.string"))
        XCTAssertTrue(source.contains("ShareLink(item:"))
        XCTAssertTrue(source.contains("Link(destination:"))
    }

    func testUnpairedContentViewDelegatesToFocusedGuideView() throws {
        let source = try readProjectSource("PingMobile/ContentView.swift")
        let unpaired = try extract(
            "private var unpairedView: some View",
            through: ".sheet(isPresented: $showScanner)",
            from: source
        )

        XCTAssertTrue(unpaired.contains("DesktopInstallGuideView"))
        XCTAssertFalse(unpaired.contains("Text(\"Mac과 연결하기\")"))
        XCTAssertFalse(unpaired.contains(".task { await PushRegistrar.shared.registerIfPossible() }"))
    }

    private func readProjectSource(_ relativePath: String) throws -> String {
        let testsDir = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
        let projectRoot = testsDir.deletingLastPathComponent()
        return try String(contentsOf: projectRoot.appendingPathComponent(relativePath), encoding: .utf8)
    }

    private func extract(_ start: String, through end: String, from contents: String) throws -> String {
        let startRange = try XCTUnwrap(contents.range(of: start))
        let tail = contents[startRange.lowerBound...]
        let endRange = try XCTUnwrap(tail.range(of: end))
        return String(tail[..<endRange.upperBound])
    }
}
```

- [ ] **Step 2: Run the failing contract tests**

Run:

```bash
xcodebuild -project Ping.xcodeproj -scheme Ping -destination "platform=macOS" test -only-testing:PingTests/PingMobileOnboardingContractTests
```

Expected: FAIL because `DesktopInstallGuideView.swift` does not exist.

- [ ] **Step 3: Create the install guide view**

Create `PingMobile/DesktopInstallGuideView.swift`. Keep the UI native and Apple-system aligned: use SF Symbols, semantic UIKit colors, standard `Button`/`ShareLink`/`Link` styles, and compact grouped cards only where they match existing iOS settings/list conventions.

```swift
import PingKit
import SwiftUI
import UIKit

struct DesktopInstallGuideView: View {
    let onScanQR: () -> Void
    let onPreview: () -> Void

    @State private var copied = false

    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                Spacer(minLength: 12)

                Image(systemName: "macbook.and.iphone")
                    .font(.system(size: 58, weight: .semibold))
                    .foregroundStyle(Color.accentColor)
                    .accessibilityHidden(true)

                VStack(spacing: 8) {
                    Text("Ping은 Mac용 Ping의 iPhone companion입니다")
                        .font(.title2.bold())
                        .multilineTextAlignment(.center)

                    Text("Mac에서 3초 영상을 보내고, iPhone과 Apple Watch에서 바로 보고 답장해요. 먼저 Mac에 Ping을 설치한 뒤 QR로 연결하세요.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                }

                VStack(alignment: .leading, spacing: 12) {
                    setupStep(number: "1", title: "Mac에서 설치 페이지 열기", detail: PingProductLinks.desktopInstallPageText)
                    setupStep(number: "2", title: "Ping 설치 후 기기 QR 표시", detail: "Mac Ping > 설정 > 기기")
                    setupStep(number: "3", title: "이 iPhone으로 QR 스캔", detail: "같은 익명 계정으로 연결됩니다")
                }
                .padding(18)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .fill(Color(uiColor: .secondarySystemBackground))
                )

                VStack(spacing: 10) {
                    Button(action: copyInstallURL) {
                        Label(copied ? "복사됐어요" : "Mac 설치 링크 복사", systemImage: copied ? "checkmark" : "doc.on.doc")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)

                    HStack(spacing: 10) {
                        ShareLink(item: PingProductLinks.desktopInstallPage) {
                            Label("Mac으로 공유", systemImage: "square.and.arrow.up")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.large)

                        Link(destination: PingProductLinks.desktopInstallPage) {
                            Label("Safari에서 보기", systemImage: "safari")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.large)
                    }

                    Button(action: onScanQR) {
                        Label("설치 끝났어요, QR 스캔", systemImage: "qrcode.viewfinder")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.large)
                }

                Button("앱 기능 미리보기", action: onPreview)
                    .font(.footnote)
                    .foregroundStyle(.tertiary)
                    .padding(.top, 8)
            }
            .padding(24)
        }
        .background(Color(uiColor: .systemBackground))
    }

    private func setupStep(number: String, title: String, detail: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Text(number)
                .font(.caption.bold())
                .foregroundStyle(.white)
                .frame(width: 24, height: 24)
                .background(Circle().fill(Color.accentColor))

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.subheadline.bold())
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func copyInstallURL() {
        UIPasteboard.general.string = PingProductLinks.desktopInstallPage.absoluteString
        copied = true

        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 1_600_000_000)
            copied = false
        }
    }
}
```

- [ ] **Step 4: Replace the inline unpaired UI in `ContentView`**

In `PingMobile/ContentView.swift`, replace the current `unpairedView` body with:

```swift
private var unpairedView: some View {
    DesktopInstallGuideView(
        onScanQR: {
            pairError = nil
            showScanner = true
        },
        onPreview: loadDemo
    )
    .overlay(alignment: .bottom) {
        if let pairError {
            Text(pairError)
                .font(.caption)
                .foregroundStyle(.red)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .background(.thinMaterial, in: Capsule())
                .padding(.bottom, 18)
        }
    }
    .sheet(isPresented: $showScanner) {
        QRScannerView { code in
            showScanner = false
            handleScanned(code)
        }
        .ignoresSafeArea()
    }
}
```

- [ ] **Step 5: Run the onboarding contract tests again**

Run:

```bash
xcodebuild -project Ping.xcodeproj -scheme Ping -destination "platform=macOS" test -only-testing:PingTests/PingMobileOnboardingContractTests
```

Expected: PASS.

- [ ] **Step 6: Build the iOS app**

Run:

```bash
xcodebuild -project Ping.xcodeproj -scheme PingMobile -configuration Debug -destination "platform=iOS Simulator,name=iPhone 17" build CODE_SIGNING_ALLOWED=NO
```

Expected: `** BUILD SUCCEEDED **`.

- [ ] **Step 7: Commit**

```bash
git add PingMobile/DesktopInstallGuideView.swift PingMobile/ContentView.swift PingTests/PingMobileOnboardingContractTests.swift
git commit -m "feat(ios): clarify desktop companion onboarding"
```

---

### Task 3: Defer iOS Push Permission Until After Pairing

**Files:**
- Modify: `PingMobile/AppDelegate.swift`
- Modify: `PingMobile/PushRegistrar.swift`
- Modify: `PingMobile/ContentView.swift`
- Create: `PingTests/PingMobilePushPermissionContractTests.swift`

- [ ] **Step 1: Add contract tests for permission timing**

Create `PingTests/PingMobilePushPermissionContractTests.swift`:

```swift
import XCTest

final class PingMobilePushPermissionContractTests: XCTestCase {
    func testAppDelegateDoesNotRequestPushPermissionBeforePairing() throws {
        let source = try readProjectSource("PingMobile/AppDelegate.swift")
        let launch = try extract(
            "func application(",
            through: "return true",
            from: source
        )

        XCTAssertTrue(launch.contains("center.setNotificationCategories"))
        XCTAssertFalse(launch.contains("requestAuthorization"))
        XCTAssertFalse(launch.contains("registerForRemoteNotifications"))
    }

    func testPushRegistrarOwnsPermissionRequestAfterPairing() throws {
        let source = try readProjectSource("PingMobile/PushRegistrar.swift")

        XCTAssertTrue(source.contains("func requestAuthorizationAndRegister() async"))
        XCTAssertTrue(source.contains("UNUserNotificationCenter.current().requestAuthorization"))
        XCTAssertTrue(source.contains("UIApplication.shared.registerForRemoteNotifications()"))
    }

    func testPairedContentRequestsPushRegistration() throws {
        let source = try readProjectSource("PingMobile/ContentView.swift")

        XCTAssertTrue(source.contains("await PushRegistrar.shared.requestAuthorizationAndRegister()"))
        XCTAssertTrue(source.contains("Task { await PushRegistrar.shared.requestAuthorizationAndRegister() }"))
    }

    private func readProjectSource(_ relativePath: String) throws -> String {
        let testsDir = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
        let projectRoot = testsDir.deletingLastPathComponent()
        return try String(contentsOf: projectRoot.appendingPathComponent(relativePath), encoding: .utf8)
    }

    private func extract(_ start: String, through end: String, from contents: String) throws -> String {
        let startRange = try XCTUnwrap(contents.range(of: start))
        let tail = contents[startRange.lowerBound...]
        let endRange = try XCTUnwrap(tail.range(of: end))
        return String(tail[..<endRange.upperBound])
    }
}
```

- [ ] **Step 2: Run the failing permission tests**

Run:

```bash
xcodebuild -project Ping.xcodeproj -scheme Ping -destination "platform=macOS" test -only-testing:PingTests/PingMobilePushPermissionContractTests
```

Expected: FAIL because `AppDelegate` still requests authorization on launch and `PushRegistrar` lacks the new method.

- [ ] **Step 3: Move permission request into `PushRegistrar`**

Replace `PingMobile/PushRegistrar.swift` with:

```swift
import Foundation
import PingKit
import UIKit
import UserNotifications

/// Holds the latest APNs device token and registers it with the backend once a
/// paired identity exists. Re-runs after pairing (P4) so order doesn't matter.
@MainActor
final class PushRegistrar {
    static let shared = PushRegistrar()

    private let tokenKey = "apnsDeviceToken"
    private(set) var token: String?

    func requestAuthorizationAndRegister() async {
        let granted = await withCheckedContinuation { continuation in
            UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge]) { granted, _ in
                continuation.resume(returning: granted)
            }
        }

        guard granted else { return }
        UIApplication.shared.registerForRemoteNotifications()
        await registerIfPossible()
    }

    func update(token: String) {
        self.token = token
        UserDefaults.standard.set(token, forKey: tokenKey)
        Task { await registerIfPossible() }
    }

    /// Register the stored token for the current user. No-op without a token or
    /// a paired account.
    func registerIfPossible() async {
        guard let token = token ?? UserDefaults.standard.string(forKey: tokenKey) else { return }
        guard let client = AppEnvironment.shared.makeClient() else { return }
        // TestFlight builds use the production APNs environment (see PUSH_BACKEND_SETUP.md).
        try? await client.registerDeviceToken(token, platform: "ios", environment: "production")
    }
}
```

- [ ] **Step 4: Stop prompting from `AppDelegate`**

In `PingMobile/AppDelegate.swift`, delete this launch block:

```swift
center.requestAuthorization(options: [.alert, .sound, .badge]) { granted, _ in
    guard granted else { return }
    DispatchQueue.main.async {
        application.registerForRemoteNotifications()
    }
}
```

Keep `center.delegate = self` and `center.setNotificationCategories([category])`.

- [ ] **Step 5: Request push only after pairing exists**

In `PingMobile/ContentView.swift`, change the paired root task from:

```swift
.task { await PushRegistrar.shared.registerIfPossible() }
```

to:

```swift
.task { await PushRegistrar.shared.requestAuthorizationAndRegister() }
```

In `handleScanned(_:)`, change:

```swift
Task { await PushRegistrar.shared.registerIfPossible() }
```

to:

```swift
Task { await PushRegistrar.shared.requestAuthorizationAndRegister() }
```

- [ ] **Step 6: Run the permission tests and iOS build**

Run:

```bash
xcodebuild -project Ping.xcodeproj -scheme Ping -destination "platform=macOS" test -only-testing:PingTests/PingMobilePushPermissionContractTests
xcodebuild -project Ping.xcodeproj -scheme PingMobile -configuration Debug -destination "platform=iOS Simulator,name=iPhone 17" build CODE_SIGNING_ALLOWED=NO
```

Expected: tests PASS and iOS build succeeds.

- [ ] **Step 7: Commit**

```bash
git add PingMobile/AppDelegate.swift PingMobile/PushRegistrar.swift PingMobile/ContentView.swift PingTests/PingMobilePushPermissionContractTests.swift
git commit -m "fix(ios): defer push permission until pairing"
```

---

### Task 4: Mobile Room Timestamp Reveal Tests

**Files:**
- Create: `PingTests/PingMobileTimestampRevealContractTests.swift`

- [ ] **Step 1: Add failing source contract tests for iMessage-style reveal**

Create `PingTests/PingMobileTimestampRevealContractTests.swift`:

```swift
import XCTest

final class PingMobileTimestampRevealContractTests: XCTestCase {
    func testThreadViewUsesSharedHorizontalTimestampRevealOffset() throws {
        let source = try readProjectSource("PingMobile/ThreadView.swift")

        XCTAssertTrue(source.contains("@State private var timestampRevealOffset: CGFloat = 0"))
        XCTAssertTrue(source.contains("private let timestampWidth: CGFloat = 64"))
        XCTAssertTrue(source.contains("private let timestampGap: CGFloat = 12"))
        XCTAssertTrue(source.contains("private var timestampRevealMax: CGFloat"))
        XCTAssertTrue(source.contains("private let timestampResetAnimation: Animation"))
    }

    func testThreadViewRevealsTimestampsBehindRows() throws {
        let source = try readProjectSource("PingMobile/ThreadView.swift")
        let row = try extract(
            "private func timestampRevealRow",
            through: "private func timestampLabel",
            from: source
        )

        XCTAssertTrue(row.contains("ZStack(alignment: .trailing)"))
        XCTAssertTrue(row.contains("timestampLabel(for: item)"))
        XCTAssertTrue(row.contains("row(item)"))
        XCTAssertTrue(row.contains(".offset(x: timestampRevealOffset)"))
    }

    func testThreadViewGestureOnlyRespondsToHorizontalLeftDrag() throws {
        let source = try readProjectSource("PingMobile/ThreadView.swift")
        let gesture = try extract(
            "private var timestampRevealGesture",
            through: "private func updateTimestampRevealOffset",
            from: source
        )

        XCTAssertTrue(gesture.contains("DragGesture(minimumDistance: 10)"))
        XCTAssertTrue(gesture.contains("abs(value.translation.width) > abs(value.translation.height)"))
        XCTAssertTrue(gesture.contains("value.translation.width < 0"))
        XCTAssertTrue(gesture.contains("resetTimestampRevealOffset()"))
    }

    private func readProjectSource(_ relativePath: String) throws -> String {
        let testsDir = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
        let projectRoot = testsDir.deletingLastPathComponent()
        return try String(contentsOf: projectRoot.appendingPathComponent(relativePath), encoding: .utf8)
    }

    private func extract(_ start: String, through end: String, from contents: String) throws -> String {
        let startRange = try XCTUnwrap(contents.range(of: start))
        let tail = contents[startRange.lowerBound...]
        let endRange = try XCTUnwrap(tail.range(of: end))
        return String(tail[..<endRange.upperBound])
    }
}
```

- [ ] **Step 2: Run the failing timestamp tests**

Run:

```bash
xcodebuild -project Ping.xcodeproj -scheme Ping -destination "platform=macOS" test -only-testing:PingTests/PingMobileTimestampRevealContractTests
```

Expected: FAIL because `ThreadView` has no timestamp reveal state or gesture.

- [ ] **Step 3: Commit the failing tests**

```bash
git add PingTests/PingMobileTimestampRevealContractTests.swift
git commit -m "test(ios): cover room timestamp reveal contract"
```

---

### Task 5: Implement Mobile Timestamp Reveal in `ThreadView`

**Files:**
- Modify: `PingMobile/ThreadView.swift`

- [ ] **Step 1: Add timestamp reveal state and constants**

In `ThreadView`, below `@StateObject private var thumbnails = ThumbnailStore()`, add:

```swift
@State private var timestampRevealOffset: CGFloat = 0

private let timestampWidth: CGFloat = 64
private let timestampGap: CGFloat = 12
private let timestampResetAnimation: Animation = .easeOut(duration: 0.10)
private var timestampRevealMax: CGFloat { -(timestampWidth + timestampGap) }
```

- [ ] **Step 2: Render rows through a timestamp reveal wrapper**

In the `ForEach(items)` block, replace:

```swift
row(item).id(item.id)
```

with:

```swift
timestampRevealRow(for: item).id(item.id)
```

- [ ] **Step 3: Attach the drag gesture to the scroll surface**

On the `ScrollView` in `ThreadView.body`, after `.overlay { if isLoading && items.isEmpty { ProgressView() } }`, add:

```swift
.simultaneousGesture(timestampRevealGesture)
```

- [ ] **Step 4: Add the reveal row and timestamp label helpers**

Add these helpers above `// MARK: - Rows`:

```swift
private func timestampRevealRow(for item: ThreadItem) -> some View {
    ZStack(alignment: .trailing) {
        timestampLabel(for: item)
        row(item)
            .offset(x: timestampRevealOffset)
    }
}

private func timestampLabel(for item: ThreadItem) -> some View {
    Text(item.date.formatted(.dateTime.hour().minute()))
        .font(.caption2)
        .foregroundStyle(.tertiary)
        .frame(width: timestampWidth, alignment: .leading)
        .opacity(min(1, abs(timestampRevealOffset) / (timestampWidth * 0.7)))
        .allowsHitTesting(false)
}
```

- [ ] **Step 5: Add gesture and offset helpers**

Add these helpers near `// MARK: - Actions`:

```swift
private var timestampRevealGesture: some Gesture {
    DragGesture(minimumDistance: 10)
        .onChanged { value in
            guard abs(value.translation.width) > abs(value.translation.height) else { return }

            if value.translation.width < 0 || timestampRevealOffset != 0 {
                updateTimestampRevealOffset(value.translation.width)
            }
        }
        .onEnded { _ in
            resetTimestampRevealOffset()
        }
}

private func updateTimestampRevealOffset(_ value: CGFloat) {
    let clamped = min(0, max(timestampRevealMax, value))
    guard abs(clamped - timestampRevealOffset) >= 0.5 else { return }

    var transaction = Transaction()
    transaction.animation = nil
    withTransaction(transaction) {
        timestampRevealOffset = clamped
    }
}

private func resetTimestampRevealOffset() {
    guard timestampRevealOffset != 0 else { return }
    withAnimation(timestampResetAnimation) {
        timestampRevealOffset = 0
    }
}
```

- [ ] **Step 6: Run timestamp tests**

Run:

```bash
xcodebuild -project Ping.xcodeproj -scheme Ping -destination "platform=macOS" test -only-testing:PingTests/PingMobileTimestampRevealContractTests
```

Expected: PASS.

- [ ] **Step 7: Build the iOS app**

Run:

```bash
xcodebuild -project Ping.xcodeproj -scheme PingMobile -configuration Debug -destination "platform=iOS Simulator,name=iPhone 17" build CODE_SIGNING_ALLOWED=NO
```

Expected: `** BUILD SUCCEEDED **`.

- [ ] **Step 8: Manual simulator QA**

Run the app on an iPhone simulator or device, pair/load demo, open a room thread, then verify:

- Vertical scrolling remains smooth.
- Dragging left on the room list area reveals a timestamp for every visible video/chat row.
- Releasing the drag springs rows back quickly.
- Tapping video thumbnails still opens playback.
- Text entry and send still work.

- [ ] **Step 9: Commit**

```bash
git add PingMobile/ThreadView.swift
git commit -m "feat(ios): reveal room timestamps on swipe"
```

---

### Task 6: Documentation and Final Verification

**Files:**
- Modify: `docs/IOS_APP_STORE_SUBMISSION.md`
- Modify: `docs/APPLE_WATCH_USER_GUIDE.md`

- [ ] **Step 1: Update App Store review guidance**

In `docs/IOS_APP_STORE_SUBMISSION.md`, update the reviewer demo section to mention that the unpaired screen now includes the desktop install link and share/copy options:

```markdown
폰 앱은 Mac/Windows 데스크톱 앱의 companion입니다. 페어링 전 화면은 이 점을 설명하고,
`https://0minping.vercel.app` 설치 링크 복사/공유/Safari 열기와 "설치 끝났어요, QR 스캔"을 제공합니다.
리뷰어는 하단 "앱 기능 미리보기"로 동반 데스크톱 없이 주요 UI를 볼 수 있습니다.
```

- [ ] **Step 2: Update user guide pairing instructions**

In `docs/APPLE_WATCH_USER_GUIDE.md`, update the pairing checklist to include:

```markdown
- iPhone Ping 첫 화면에서 `Mac 설치 링크 복사` 또는 `Mac으로 공유`를 사용해 Mac에서 `https://0minping.vercel.app`를 연다.
- Mac Ping 설치 후 설정 → 기기 탭의 QR을 iPhone Ping의 `설치 끝났어요, QR 스캔`으로 스캔한다.
```

- [ ] **Step 3: Run all relevant automated checks**

Run:

```bash
swift test --package-path PingKit
xcodebuild -project Ping.xcodeproj -scheme Ping -destination "platform=macOS" test
xcodebuild -project Ping.xcodeproj -scheme PingMobile -configuration Debug -destination "platform=iOS Simulator,name=iPhone 17" build CODE_SIGNING_ALLOWED=NO
```

Expected: all tests pass and iOS build succeeds.

- [ ] **Step 4: Commit docs**

```bash
git add docs/IOS_APP_STORE_SUBMISSION.md docs/APPLE_WATCH_USER_GUIDE.md
git commit -m "docs(ios): document desktop companion onboarding"
```

---

## Acceptance Criteria

- A first-time iPhone user can tell from the first screen that Ping requires the Mac desktop app.
- The first screen exposes `https://0minping.vercel.app` through copy, share sheet, and Safari open actions.
- QR scanning remains the only account-linking path; the secure desktop handoff payload is unchanged.
- Notification permission is not requested before the user understands and completes pairing.
- Mobile room threads reveal per-message timestamps when the user drags left, matching the macOS behavior closely enough for iPhone touch interaction.
- Video playback, chat send, demo mode, and QR pairing still build and work.

## Execution Choice

Recommended execution mode: Subagent-Driven for Tasks 1-6, with review after each commit. Inline execution is also reasonable because the code surface is small, but timestamp gesture QA benefits from a focused review pass.
