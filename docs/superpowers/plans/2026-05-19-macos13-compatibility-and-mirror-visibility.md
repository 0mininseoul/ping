# macOS 13 Compatibility and Mirror Visibility Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Ship a new Ping update that supports macOS 13.0+ and guarantees Option+P always presents the circular mirror on the current visible screen.

**Architecture:** Fix mirror presentation by extracting persisted window positioning into a pure, testable helper and clamping stale/off-screen saved origins before every presentation. Lower the deployment target to macOS 13.0 by routing direct Liquid Glass calls through a small SwiftUI compatibility modifier that keeps `.glassEffect()` on macOS 26+ and uses the existing stable tinted surfaces on macOS 13-25. Update the app, tests, docs, website, and Sparkle release metadata as one versioned compatibility release.

**Tech Stack:** Swift 6, SwiftUI, AppKit, AVFoundation, XcodeGen, KeyboardShortcuts, Sparkle 2, XCTest, Supabase.

---

## Investigation Outcome

Current local evidence for the Option+P issue:

- `defaults read com.youngminpark.ping.Ping ping.mirror.lastPosition` returned `{ x = 2521; y = 361; }`.
- The current screen frame from `NSScreen.screens` is `(0.0, 0.0, 1800.0, 1169.0)`.
- `Ping/AppDelegate.swift` does call `startCameraForMirrorPresentation()` before `mirrorWindow?.makeKeyAndOrderFront(nil)`.
- `Ping/UI/Mirror/MirrorWindow.swift` loads the saved origin without clamping it to `NSScreen.main?.visibleFrame`.

Root cause: the hotkey works and starts the camera, but the mirror window is restored at a stale off-screen x coordinate. The user sees only the camera indicator because the window is alive but outside the visible display.

Immediate local recovery, before the code fix is shipped:

```bash
defaults delete com.youngminpark.ping.Ping ping.mirror.lastPosition
osascript -e 'tell application "Ping" to quit'
open /Applications/Ping.app
```

macOS 13 audit result:

```bash
xcodebuild -project Ping.xcodeproj -scheme Ping -configuration Debug \
  -destination "platform=macOS" -derivedDataPath build-macos13-audit \
  MACOSX_DEPLOYMENT_TARGET=13.0 build
```

Expected current failure:

```text
Ping/UI/Glass/GlassChip.swift:32:18: error: 'glassEffect(_:in:)' is only available in macOS 26.0 or newer
```

Direct `.glassEffect()` call sites to migrate:

- `Ping/UI/Glass/GlassChip.swift`
- `Ping/UI/Mirror/PartnerPicker.swift`
- `Ping/UI/Mirror/MirrorView.swift`

SwiftUI two-argument `.onChange` call sites to migrate for macOS 13:

- `Ping/UI/Setup/RoomListView.swift`
- `Ping/UI/Setup/SettingsScene.swift`

## File Structure

- Create `Ping/Core/WindowPositioning.swift`: pure window-origin helper for persisted mirror positions.
- Modify `Ping/UI/Mirror/MirrorWindow.swift`: clamp loaded/saved positions and expose `ensureVisibleOnCurrentScreen()`.
- Modify `Ping/AppDelegate.swift`: call `ensureVisibleOnCurrentScreen()` before showing the mirror.
- Create `PingTests/WindowPositioningTests.swift`: regression coverage for the exact off-screen position found locally.
- Create `Ping/UI/Glass/GlassEffectCompat.swift`: one compatibility wrapper for `.glassEffect()`.
- Modify `Ping/UI/Glass/GlassChip.swift`: replace direct `.glassEffect()` with `.pingGlassEffect()`.
- Modify `Ping/UI/Mirror/PartnerPicker.swift`: use a filled fallback surface plus `.pingGlassEffect()`.
- Modify `Ping/UI/Mirror/MirrorView.swift`: use a filled fallback surface plus `.pingGlassEffect()` for the uploading chip.
- Modify `Ping/UI/Setup/RoomListView.swift` and `Ping/UI/Setup/SettingsScene.swift`: replace two-argument `.onChange` closures with macOS 13-compatible one-argument closures.
- Modify `project.yml` and `Ping/Info.plist`: set macOS minimum to `13.0`, bump app version to `0.1.4`, and include new source files in test fixture copying where needed.
- Modify `AGENTS.md`, `PING_PROJECT_SPECIFICATION.md`, `README.md`, `docs/superpowers/plans/2026-05-17-ping-mvp.md`, and website copy under `web/src`: replace the old macOS 26-only invariant with the new macOS 13+ compatibility rule.
- Modify `PingTests/ReleaseVersionContractTests.swift` and add compatibility contract tests for minimum OS text and no direct `.glassEffect()` outside the compatibility file.

---

### Task 1: Clamp Persisted Mirror Position

**Files:**
- Create: `Ping/Core/WindowPositioning.swift`
- Modify: `Ping/UI/Mirror/MirrorWindow.swift`
- Modify: `Ping/AppDelegate.swift`
- Test: `PingTests/WindowPositioningTests.swift`

- [ ] **Step 1: Write the failing positioning tests**

Create `PingTests/WindowPositioningTests.swift`:

```swift
import XCTest
@testable import Ping

final class WindowPositioningTests: XCTestCase {
    func testVisibleOriginClampsSavedMirrorPositionFromCurrentMac() {
        let visibleFrame = CGRect(x: 0, y: 47, width: 1800, height: 1083)
        let origin = WindowPositioning.visibleOrigin(
            preferred: CGPoint(x: 2521, y: 361),
            windowSize: CGSize(width: 200, height: 200),
            in: visibleFrame
        )

        XCTAssertEqual(origin.x, 1600, accuracy: 0.0001)
        XCTAssertEqual(origin.y, 361, accuracy: 0.0001)
    }

    func testVisibleOriginCentersWindowWhenNoSavedPositionExists() {
        let visibleFrame = CGRect(x: 0, y: 47, width: 1800, height: 1083)
        let origin = WindowPositioning.visibleOrigin(
            preferred: nil,
            windowSize: CGSize(width: 200, height: 200),
            in: visibleFrame
        )

        XCTAssertEqual(origin.x, 800, accuracy: 0.0001)
        XCTAssertEqual(origin.y, 488.5, accuracy: 0.0001)
    }

    func testVisibleOriginHandlesEmptyScreenFrame() {
        let origin = WindowPositioning.visibleOrigin(
            preferred: CGPoint(x: 2521, y: 361),
            windowSize: CGSize(width: 200, height: 200),
            in: .zero
        )

        XCTAssertEqual(origin.x, 0, accuracy: 0.0001)
        XCTAssertEqual(origin.y, 0, accuracy: 0.0001)
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run:

```bash
xcodebuild -project Ping.xcodeproj -scheme Ping \
  -destination "platform=macOS" \
  -only-testing:PingTests/WindowPositioningTests test
```

Expected: FAIL because `WindowPositioning` does not exist.

- [ ] **Step 3: Implement the pure positioning helper**

Create `Ping/Core/WindowPositioning.swift`:

```swift
import CoreGraphics

enum WindowPositioning {
    static func visibleOrigin(
        preferred: CGPoint?,
        windowSize: CGSize,
        in visibleFrame: CGRect
    ) -> CGPoint {
        guard visibleFrame.width > 0, visibleFrame.height > 0 else {
            return .zero
        }

        let candidate = preferred ?? centeredOrigin(windowSize: windowSize, in: visibleFrame)

        return ScreenCoordinates.clamp(
            point: candidate,
            windowSize: windowSize,
            inSafeArea: visibleFrame
        )
    }

    private static func centeredOrigin(windowSize: CGSize, in visibleFrame: CGRect) -> CGPoint {
        CGPoint(
            x: visibleFrame.midX - windowSize.width / 2,
            y: visibleFrame.midY - windowSize.height / 2
        )
    }
}
```

- [ ] **Step 4: Use the helper in MirrorWindow**

Modify `Ping/UI/Mirror/MirrorWindow.swift`:

```swift
import AppKit
import SwiftUI

@MainActor
final class MirrorWindow: NSWindow {
    static let size = NSSize(width: 200, height: 200)
    private static let positionKey = "ping.mirror.lastPosition"

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }

    init<Content: View>(rootView: Content) {
        let initialRect = NSRect(origin: Self.loadLastPosition(), size: Self.size)
        super.init(
            contentRect: initialRect,
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        isOpaque = false
        backgroundColor = .clear
        level = .floating
        hasShadow = false
        isMovableByWindowBackground = true
        ignoresMouseEvents = false
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]

        let host = NSHostingView(rootView: AnyView(rootView))
        host.frame = NSRect(origin: .zero, size: Self.size)
        contentView = host
    }

    static func loadLastPosition() -> NSPoint {
        guard let screen = NSScreen.main else { return .zero }

        return WindowPositioning.visibleOrigin(
            preferred: savedPosition(),
            windowSize: size,
            in: screen.visibleFrame
        )
    }

    func ensureVisibleOnCurrentScreen() {
        guard let screen = screenForCurrentFrame() ?? NSScreen.main else { return }
        let origin = WindowPositioning.visibleOrigin(
            preferred: frame.origin,
            windowSize: frame.size,
            in: screen.visibleFrame
        )
        setFrameOrigin(origin)
    }

    func savePosition() {
        UserDefaults.standard.set(
            ["x": frame.origin.x, "y": frame.origin.y],
            forKey: Self.positionKey
        )
    }

    override func mouseUp(with event: NSEvent) {
        super.mouseUp(with: event)
        savePosition()
    }

    private static func savedPosition() -> NSPoint? {
        let defaults = UserDefaults.standard
        guard let dict = defaults.dictionary(forKey: positionKey),
              let x = dict["x"] as? CGFloat,
              let y = dict["y"] as? CGFloat else {
            return nil
        }

        return NSPoint(x: x, y: y)
    }

    private func screenForCurrentFrame() -> NSScreen? {
        NSScreen.screens.first { screen in
            screen.frame.intersects(frame)
        }
    }
}
```

- [ ] **Step 5: Clamp before every mirror presentation**

Modify `Ping/AppDelegate.swift` inside `private func toggleMirror()` so the show path is:

```swift
mirrorViewModel.reset()
mirrorWindow?.ensureVisibleOnCurrentScreen()
startCameraForMirrorPresentation()
mirrorWindow?.makeKeyAndOrderFront(nil)
NSApp.activate(ignoringOtherApps: true)
```

- [ ] **Step 6: Run the focused tests**

Run:

```bash
xcodebuild -project Ping.xcodeproj -scheme Ping \
  -destination "platform=macOS" \
  -only-testing:PingTests/WindowPositioningTests test
```

Expected: PASS.

- [ ] **Step 7: Commit**

```bash
git add Ping/Core/WindowPositioning.swift Ping/UI/Mirror/MirrorWindow.swift Ping/AppDelegate.swift PingTests/WindowPositioningTests.swift
git commit -m "fix(mirror): clamp saved window position"
```

---

### Task 2: Add Liquid Glass Compatibility Wrapper

**Files:**
- Create: `Ping/UI/Glass/GlassEffectCompat.swift`
- Modify: `Ping/UI/Glass/GlassChip.swift`
- Modify: `Ping/UI/Mirror/PartnerPicker.swift`
- Modify: `Ping/UI/Mirror/MirrorView.swift`
- Test: `PingTests/DesignSystemContractTests.swift`
- Modify: `project.yml`

- [ ] **Step 1: Add a contract test that direct glass calls are isolated**

Modify `PingTests/DesignSystemContractTests.swift`:

```swift
func testGlassEffectIsIsolatedBehindCompatibilityModifier() throws {
    let glassCompat = try readSourceFile("Ping/UI/Glass/GlassEffectCompat.swift")
    let glassChip = try readSourceFile("Ping/UI/Glass/GlassChip.swift")
    let partnerPicker = try readSourceFile("Ping/UI/Mirror/PartnerPicker.swift")
    let mirrorView = try readSourceFile("Ping/UI/Mirror/MirrorView.swift")

    XCTAssertTrue(glassCompat.contains("if #available(macOS 26.0, *)"))
    XCTAssertTrue(glassCompat.contains(".glassEffect()"))
    XCTAssertFalse(glassChip.contains(".glassEffect()"))
    XCTAssertFalse(partnerPicker.contains(".glassEffect()"))
    XCTAssertFalse(mirrorView.contains(".glassEffect()"))
    XCTAssertTrue(glassChip.contains(".pingGlassEffect()"))
    XCTAssertTrue(partnerPicker.contains(".pingGlassEffect()"))
    XCTAssertTrue(mirrorView.contains(".pingGlassEffect()"))
}
```

Also add `GlassEffectCompat.swift` to the `Copy Contract Test Fixtures` script in `project.yml`:

```yaml
          cp "$PROJECT_DIR/Ping/UI/Glass/GlassEffectCompat.swift" "$DST/GlassEffectCompat.swift"
```

Add the matching input and output entries:

```yaml
          - "$(PROJECT_DIR)/Ping/UI/Glass/GlassEffectCompat.swift"
```

```yaml
          - "$(TARGET_BUILD_DIR)/$(CONTENTS_FOLDER_PATH)/Resources/GlassEffectCompat.swift"
```

- [ ] **Step 2: Run test to verify it fails**

Run:

```bash
xcodegen generate
xcodebuild -project Ping.xcodeproj -scheme Ping \
  -destination "platform=macOS" \
  -only-testing:PingTests/DesignSystemContractTests/testGlassEffectIsIsolatedBehindCompatibilityModifier test
```

Expected: FAIL because `GlassEffectCompat.swift` does not exist and direct `.glassEffect()` calls remain.

- [ ] **Step 3: Create the compatibility modifier**

Create `Ping/UI/Glass/GlassEffectCompat.swift`:

```swift
import SwiftUI

private struct PingGlassEffectModifier: ViewModifier {
    @ViewBuilder
    func body(content: Content) -> some View {
        if #available(macOS 26.0, *) {
            content.glassEffect()
        } else {
            content
        }
    }
}

extension View {
    func pingGlassEffect() -> some View {
        modifier(PingGlassEffectModifier())
    }
}
```

- [ ] **Step 4: Replace direct glass use in GlassChip**

In `Ping/UI/Glass/GlassChip.swift`, replace:

```swift
.glassEffect()
```

with:

```swift
.pingGlassEffect()
```

The background block must remain:

```swift
.background {
    Capsule()
        .fill(PingDesign.Surface.rowFill.opacity(isHover ? 0.95 : 0.78))
        .pingGlassEffect()
        .overlay {
            Capsule()
                .strokeBorder(
                    PingDesign.Surface.strongHairline.opacity(isHover ? 0.86 : 0.56),
                    lineWidth: 0.8
                )
        }
}
```

- [ ] **Step 5: Replace direct glass use in PartnerPicker**

In `Ping/UI/Mirror/PartnerPicker.swift`, replace the dropdown background with:

```swift
.background {
    RoundedRectangle(cornerRadius: 10, style: .continuous)
        .fill(PingDesign.Surface.panelFill.opacity(0.94))
        .pingGlassEffect()
        .overlay {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(PingDesign.Surface.strongHairline.opacity(0.42), lineWidth: 0.8)
        }
}
```

- [ ] **Step 6: Replace direct glass use in MirrorView**

In `Ping/UI/Mirror/MirrorView.swift`, replace the uploading chip background with:

```swift
.background {
    Capsule()
        .fill(PingDesign.Surface.rowFill.opacity(0.84))
        .pingGlassEffect()
        .overlay {
            Capsule()
                .strokeBorder(PingDesign.Surface.strongHairline.opacity(0.48), lineWidth: 0.8)
        }
}
```

- [ ] **Step 7: Run the focused contract test**

Run:

```bash
xcodegen generate
xcodebuild -project Ping.xcodeproj -scheme Ping \
  -destination "platform=macOS" \
  -only-testing:PingTests/DesignSystemContractTests/testGlassEffectIsIsolatedBehindCompatibilityModifier test
```

Expected: PASS.

- [ ] **Step 8: Commit**

```bash
git add Ping/UI/Glass/GlassEffectCompat.swift Ping/UI/Glass/GlassChip.swift Ping/UI/Mirror/PartnerPicker.swift Ping/UI/Mirror/MirrorView.swift PingTests/DesignSystemContractTests.swift project.yml
git commit -m "feat(ui): add glass effect compatibility layer"
```

---

### Task 3: Replace macOS 14-Only onChange Closures

**Files:**
- Modify: `Ping/UI/Setup/RoomListView.swift`
- Modify: `Ping/UI/Setup/SettingsScene.swift`

- [ ] **Step 1: Change RoomListView onChange to the macOS 13 signature**

In `Ping/UI/Setup/RoomListView.swift`, replace:

```swift
.onChange(of: focusedEditingRoomId) { _, newValue in
    if editingRoomId == roomId, newValue != roomId {
        commitRename(room)
    }
}
```

with:

```swift
.onChange(of: focusedEditingRoomId) { newValue in
    if editingRoomId == roomId, newValue != roomId {
        commitRename(room)
    }
}
```

- [ ] **Step 2: Change General settings onChange closures**

In `Ping/UI/Setup/SettingsScene.swift`, replace:

```swift
.onChange(of: autoLaunchEnabled) { _, newValue in
    updateAutoLaunch(newValue)
}
```

with:

```swift
.onChange(of: autoLaunchEnabled) { newValue in
    updateAutoLaunch(newValue)
}
```

Replace:

```swift
.onChange(of: appState.currentUser?.nickname) { _, newValue in
    nicknameDraft = newValue ?? ""
}
.onChange(of: appearanceMode) { _, newValue in
    (PingAppearanceMode(rawValue: newValue) ?? .system).apply()
}
```

with:

```swift
.onChange(of: appState.currentUser?.nickname) { newValue in
    nicknameDraft = newValue ?? ""
}
.onChange(of: appearanceMode) { newValue in
    (PingAppearanceMode(rawValue: newValue) ?? .system).apply()
}
```

- [ ] **Step 3: Change Storage settings onChange closures**

In `Ping/UI/Setup/SettingsScene.swift`, replace:

```swift
.onChange(of: autoDeleteAfter30Days) { _, enabled in
    LocalArchive.autoDeleteAfter30Days = enabled
}
```

with:

```swift
.onChange(of: autoDeleteAfter30Days) { enabled in
    LocalArchive.autoDeleteAfter30Days = enabled
}
```

Replace:

```swift
.onChange(of: saveSentEnabled) { _, newValue in
    LocalArchive.saveSentEnabled = newValue
}
.onChange(of: saveReceivedEnabled) { _, newValue in
    LocalArchive.saveReceivedEnabled = newValue
}
```

with:

```swift
.onChange(of: saveSentEnabled) { newValue in
    LocalArchive.saveSentEnabled = newValue
}
.onChange(of: saveReceivedEnabled) { newValue in
    LocalArchive.saveReceivedEnabled = newValue
}
```

- [ ] **Step 4: Confirm no two-argument onChange call remains**

Run:

```bash
rg -n "onChange\\(of:.*\\{ _,|onChange\\(of:.*\\{ [^ ]+, [^ ]+ in" Ping
```

Expected: no output.

- [ ] **Step 5: Build with macOS 13 deployment override**

Run:

```bash
xcodebuild -project Ping.xcodeproj -scheme Ping -configuration Debug \
  -destination "platform=macOS" \
  -derivedDataPath build-macos13-audit \
  MACOSX_DEPLOYMENT_TARGET=13.0 build
```

Expected: no `.glassEffect()` or `.onChange` availability errors.

- [ ] **Step 6: Clean audit build output**

Run:

```bash
rm -r build-macos13-audit
```

Expected: `git status --short` does not show `build-macos13-audit/`.

- [ ] **Step 7: Commit**

```bash
git add Ping/UI/Setup/RoomListView.swift Ping/UI/Setup/SettingsScene.swift
git commit -m "fix(ui): use macOS 13 compatible change handlers"
```

---

### Task 4: Lower Minimum macOS and Update Product Invariants

**Files:**
- Modify: `project.yml`
- Modify: `Ping/Info.plist`
- Modify: `AGENTS.md`
- Modify: `PING_PROJECT_SPECIFICATION.md`
- Modify: `docs/superpowers/plans/2026-05-17-ping-mvp.md`
- Modify: `README.md`
- Modify: `PingTests/ReleaseVersionContractTests.swift`
- Create or modify: `PingTests/CompatibilityContractTests.swift`

- [ ] **Step 1: Add compatibility contract tests**

Create `PingTests/CompatibilityContractTests.swift`:

```swift
import XCTest

final class CompatibilityContractTests: XCTestCase {
    func testProjectTargetsMacOS13AndSwift6() throws {
        let project = try readSourceFile("project.yml")
        let info = try readSourceFile("Ping/Info.plist")

        XCTAssertTrue(project.contains("macOS: \"13.0\""))
        XCTAssertTrue(project.contains("MACOSX_DEPLOYMENT_TARGET: \"13.0\""))
        XCTAssertTrue(project.contains("deploymentTarget: \"13.0\""))
        XCTAssertTrue(project.contains("SWIFT_VERSION: \"6.0\""))
        XCTAssertTrue(info.contains("<string>13.0</string>"))
    }

    func testDocsNoLongerDescribeAppAsMacOS26Only() throws {
        let spec = try readSourceFile("PING_PROJECT_SPECIFICATION.md")
        let readme = try readSourceFile("README.md")
        let agents = try readSourceFile("AGENTS.md")

        XCTAssertTrue(spec.contains("macOS 13 Ventura 이상"))
        XCTAssertTrue(readme.contains("macOS 13 Ventura 이상"))
        XCTAssertTrue(agents.contains("macOS 13 Ventura 이상"))
        XCTAssertFalse(spec.contains("macOS 26 Tahoe 전용"))
        XCTAssertFalse(readme.contains("macOS 26 Tahoe 이상"))
        XCTAssertFalse(agents.contains("deploymentTarget 낮추지 말 것"))
    }

    private func readSourceFile(_ relativePath: String) throws -> String {
        let fileName = URL(fileURLWithPath: relativePath).lastPathComponent
        let fileURL = try XCTUnwrap(Bundle(for: Self.self).resourceURL?.appendingPathComponent(fileName))

        return try String(contentsOf: fileURL, encoding: .utf8)
    }
}
```

Add these files to the `Copy Contract Test Fixtures` script in `project.yml`:

```yaml
          cp "$PROJECT_DIR/AGENTS.md" "$DST/AGENTS.md"
          cp "$PROJECT_DIR/PING_PROJECT_SPECIFICATION.md" "$DST/PING_PROJECT_SPECIFICATION.md"
          cp "$PROJECT_DIR/Ping/Info.plist" "$DST/Info.plist"
```

Add the matching input and output entries:

```yaml
          - "$(PROJECT_DIR)/AGENTS.md"
          - "$(PROJECT_DIR)/PING_PROJECT_SPECIFICATION.md"
          - "$(PROJECT_DIR)/Ping/Info.plist"
```

```yaml
          - "$(TARGET_BUILD_DIR)/$(CONTENTS_FOLDER_PATH)/Resources/AGENTS.md"
          - "$(TARGET_BUILD_DIR)/$(CONTENTS_FOLDER_PATH)/Resources/PING_PROJECT_SPECIFICATION.md"
          - "$(TARGET_BUILD_DIR)/$(CONTENTS_FOLDER_PATH)/Resources/Info.plist"
```

- [ ] **Step 2: Run tests to verify they fail**

Run:

```bash
xcodegen generate
xcodebuild -project Ping.xcodeproj -scheme Ping \
  -destination "platform=macOS" \
  -only-testing:PingTests/CompatibilityContractTests test
```

Expected: FAIL because the app still targets and documents macOS 26.

- [ ] **Step 3: Update project version and minimum OS**

Modify `project.yml`:

```yaml
options:
  deploymentTarget:
    macOS: "13.0"

settings:
  base:
    SWIFT_VERSION: "6.0"
    MACOSX_DEPLOYMENT_TARGET: "13.0"
    MARKETING_VERSION: "0.1.4"
    CURRENT_PROJECT_VERSION: "6"
```

Set both target deployment values:

```yaml
  Ping:
    deploymentTarget: "13.0"
```

```yaml
  PingTests:
    deploymentTarget: "13.0"
```

Set app minimum system version:

```yaml
        LSMinimumSystemVersion: "13.0"
```

Modify `Ping/Info.plist`:

```xml
<key>LSMinimumSystemVersion</key>
<string>13.0</string>
```

- [ ] **Step 4: Update release version contract**

Modify `PingTests/ReleaseVersionContractTests.swift`:

```swift
XCTAssertTrue(project.contains("MARKETING_VERSION: \"0.1.4\""))
XCTAssertTrue(project.contains("CURRENT_PROJECT_VERSION: \"6\""))
XCTAssertTrue(routes.contains("APP_VERSION = \"v0.1.4\""))
XCTAssertTrue(routes.contains("DOWNLOAD_URL = \"/downloads/Ping-v0.1.4.dmg\""))
XCTAssertTrue(readme.contains("Ping-v0.1.4.dmg"))
```

- [ ] **Step 5: Update agent and product docs**

Update `AGENTS.md` invariants from macOS 26-only to macOS 13+ compatibility:

```markdown
| **macOS 13 Ventura 이상** | v0.1.4부터 지원 | `MACOSX_DEPLOYMENT_TARGET`과 `LSMinimumSystemVersion`을 `13.0` 아래로 낮추지 말 것 |
| **Swift 6.0+** | 정식 릴리스 | `Swift 5.x` 로 SWIFT_VERSION 낮추지 말 것 |
| **`.pingGlassEffect()` wrapper** | macOS 26에서는 `.glassEffect()`, macOS 13-25에서는 안정 tint surface | 앱 코드에서 `.glassEffect()`를 직접 호출하지 말 것 |
| **`SMAppService.mainApp`** | macOS 13+ 모던 자동 시작 API | 구식 `LaunchAgent` plist 방식으로 바꾸지 말 것 |
```

Update `PING_PROJECT_SPECIFICATION.md`:

```markdown
**Ping**은 macOS 13 Ventura 이상에서 동작하는 2초 영상 메시지 메뉴바 앱이다.
```

System requirements table:

```markdown
| 운영체제 | macOS 13 Ventura 이상 |
| 아키텍처 | Apple Silicon Mac 우선, Intel Mac은 v0.1.4 빌드 검증 후 지원 여부 표기 |
```

Design rule:

```markdown
macOS 26 이상에서는 SwiftUI 네이티브 `.glassEffect()`를 사용하고, macOS 13-25에서는 `PingDesign.Surface` 기반 fallback surface를 사용한다. 앱 코드는 `.pingGlassEffect()` wrapper만 호출한다.
```

Update `README.md`:

```markdown
1. `Ping-v0.1.4.dmg`를 더블클릭해 마운트한다.
```

```markdown
- macOS 13 Ventura 이상
- Apple Silicon Mac 권장
```

Update `docs/superpowers/plans/2026-05-17-ping-mvp.md` so the old invariant becomes:

```markdown
- Keep `macOS: "13.0"` and `SWIFT_VERSION: "6.0"`.
- Do not call `.glassEffect()` directly outside `Ping/UI/Glass/GlassEffectCompat.swift`.
- Keep `SMAppService.mainApp`; it is available for the new macOS 13+ floor.
```

- [ ] **Step 6: Run compatibility contract tests**

Run:

```bash
xcodegen generate
xcodebuild -project Ping.xcodeproj -scheme Ping \
  -destination "platform=macOS" \
  -only-testing:PingTests/CompatibilityContractTests \
  -only-testing:PingTests/ReleaseVersionContractTests test
```

Expected: PASS.

- [ ] **Step 7: Commit**

```bash
git add project.yml Ping/Info.plist AGENTS.md PING_PROJECT_SPECIFICATION.md README.md docs/superpowers/plans/2026-05-17-ping-mvp.md PingTests/CompatibilityContractTests.swift PingTests/ReleaseVersionContractTests.swift
git commit -m "chore(release): target macOS 13 for compatibility update"
```

---

### Task 5: Update Website Copy and Download Metadata

**Files:**
- Modify: `web/package.json`
- Modify: `web/package-lock.json`
- Modify: `web/src/routes.tsx`
- Modify: `web/src/components/invite/InviteView.tsx`
- Modify: `web/src/components/sections/SpecStrip.tsx`
- Modify: `web/src/components/sections/FinalCTA.tsx`
- Modify: `web/src/components/sections/SiteFooter.tsx`
- Modify: `docs/superpowers/specs/2026-05-17-web-redesign-design.md`
- Test: existing web build or route contract tests

- [ ] **Step 1: Update web version constants**

Modify `web/package.json`:

```json
{
  "version": "0.1.4"
}
```

Modify `web/src/routes.tsx`:

```tsx
export const APP_VERSION = "v0.1.4";
export const DOWNLOAD_URL = "/downloads/Ping-v0.1.4.dmg";
```

Run:

```bash
cd web && npm install --package-lock-only
```

Expected: `web/package-lock.json` records version `0.1.4`.

- [ ] **Step 2: Update public compatibility copy**

Modify `web/src/components/invite/InviteView.tsx`:

```tsx
<span>macOS 13 Ventura 이상 · Apple Silicon Mac 권장</span>
```

Modify `web/src/components/sections/SpecStrip.tsx`:

```tsx
{ icon: <Cpu className="h-4 w-4" />, label: "Apple Silicon Mac 권장" },
{ icon: <MonitorCog className="h-4 w-4" />, label: "macOS 13 Ventura+" },
```

Modify `web/src/components/sections/FinalCTA.tsx`:

```tsx
Apple Silicon 권장 · macOS 13 Ventura+ · ~24MB
```

Modify `web/src/components/sections/SiteFooter.tsx`:

```tsx
macOS 13 Ventura 이상 · Apple Silicon Mac 권장
```

Modify `docs/superpowers/specs/2026-05-17-web-redesign-design.md`:

```markdown
- macOS 13 Ventura+ 호환성과 Apple Silicon 우선 경험을 명확히 표시
```

- [ ] **Step 3: Run web and contract checks**

Run:

```bash
cd web && npm run build
xcodebuild -project Ping.xcodeproj -scheme Ping \
  -destination "platform=macOS" \
  -only-testing:PingTests/ReleaseVersionContractTests test
```

Expected: web build succeeds and release version contract passes.

- [ ] **Step 4: Commit**

```bash
git add web/package.json web/package-lock.json web/src/routes.tsx web/src/components/invite/InviteView.tsx web/src/components/sections/SpecStrip.tsx web/src/components/sections/FinalCTA.tsx web/src/components/sections/SiteFooter.tsx docs/superpowers/specs/2026-05-17-web-redesign-design.md
git commit -m "docs(web): advertise macOS 13 compatibility"
```

---

### Task 6: Full Verification and Local Install

**Files:**
- Build output only: `build/`, `dist/`, `web/public/downloads/`, `web/public/appcast.xml`
- Commit release artifacts only if this repository intentionally tracks `web/public/appcast.xml` or web download references.

- [ ] **Step 1: Regenerate the Xcode project**

Run:

```bash
xcodegen generate
```

Expected: `Ping.xcodeproj` regenerates from `project.yml`.

- [ ] **Step 2: Run the full test suite**

Run:

```bash
xcodebuild -project Ping.xcodeproj -scheme Ping \
  -destination "platform=macOS" test
```

Expected: all tests pass.

- [ ] **Step 3: Run a clean debug build at macOS 13 floor**

Run:

```bash
xcodebuild -project Ping.xcodeproj -scheme Ping -configuration Debug \
  -destination "platform=macOS" \
  -derivedDataPath build-macos13-audit build
```

Expected: build succeeds with target `arm64-apple-macos13.0`.

- [ ] **Step 4: Clean audit build output**

Run:

```bash
rm -r build-macos13-audit
```

Expected: `git status --short` does not show `build-macos13-audit/`.

- [ ] **Step 5: Build the release DMG and appcast**

Run:

```bash
./scripts/build-release.sh
```

Expected:

```text
Built dist/Ping-v0.1.4.dmg
Copied web/public/downloads/Ping-v0.1.4.dmg
Wrote web/public/appcast.xml
```

- [ ] **Step 6: Verify Sparkle minimum system version**

Run:

```bash
rg -n "0.1.4|minimumSystemVersion" web/public/appcast.xml
```

Expected the `0.1.4` item contains:

```xml
<sparkle:minimumSystemVersion>13.0</sparkle:minimumSystemVersion>
```

- [ ] **Step 7: Install the updated local app**

Run:

```bash
osascript -e 'tell application "Ping" to quit' || true
pkill -x Ping || true
rsync -a --delete build/Build/Products/Release/Ping.app/ /Applications/Ping.app/
codesign --verify --deep --strict --verbose=2 /Applications/Ping.app
/usr/libexec/PlistBuddy -c "Print CFBundleShortVersionString" /Applications/Ping.app/Contents/Info.plist
/usr/libexec/PlistBuddy -c "Print LSMinimumSystemVersion" /Applications/Ping.app/Contents/Info.plist
open /Applications/Ping.app
```

Expected:

```text
/Applications/Ping.app: valid on disk
/Applications/Ping.app: satisfies its Designated Requirement
0.1.4
13.0
```

- [ ] **Step 8: Manually verify the original bug**

Run:

```bash
defaults write com.youngminpark.ping.Ping ping.mirror.lastPosition -dict x 2521 y 361
```

Then press `Option+P`.

Expected:

- Camera indicator turns on.
- The circular mirror appears inside the current visible screen instead of off-screen.
- Pressing `Esc` closes the mirror and turns the camera off.

- [ ] **Step 9: Commit release metadata**

If `web/public/appcast.xml`, `web/public/downloads/`, or other release metadata are tracked and changed:

```bash
git add web/public/appcast.xml web/public/downloads web/src/routes.tsx README.md project.yml Ping/Info.plist
git commit -m "release: 0.1.4"
```

If DMGs are ignored and only appcast changed:

```bash
git add web/public/appcast.xml
git commit -m "release: 0.1.4"
```

- [ ] **Step 10: Push**

Run:

```bash
git status --short --branch
git push origin main
```

Expected:

```text
## main...origin/main
```

or a clean branch status after push.

---

## Self-Review

Spec coverage:

- Mirror visibility root cause is covered by Task 1.
- macOS 13 deployment target is covered by Task 4 and verified in Task 6.
- `.glassEffect()` availability is covered by Task 2.
- macOS 13 `.onChange` compatibility is covered by Task 3.
- User-facing installation and website copy are covered by Tasks 4 and 5.
- Release, appcast, and local installed app update are covered by Task 6.

Residual risks:

- This plan verifies compilation on the current macOS 26 SDK with deployment target 13.0. A real macOS 13 machine or VM should still be used for final smoke testing before broad release.
- Intel Mac support is not guaranteed by this plan. The public copy should say Apple Silicon recommended unless an x86_64 runtime smoke test is completed.

Plan complete and saved to `docs/superpowers/plans/2026-05-19-macos13-compatibility-and-mirror-visibility.md`.

Execution options:

1. Subagent-Driven (recommended) - dispatch a fresh worker per task, review between tasks, fast iteration.
2. Inline Execution - execute tasks in this session using `superpowers:executing-plans`, batch execution with checkpoints.
