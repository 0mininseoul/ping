import AppKit
import XCTest
@testable import Ping

final class StatusMenuBuilderTests: XCTestCase {
    @MainActor
    func testVideoMenuItemShowsOptionPShortcut() {
        let menu = StatusMenuBuilder.makeMenu(target: NSObject())

        let videoItem = menu.items.first { $0.title == "영상 보내기" }

        XCTAssertNotNil(videoItem)
        XCTAssertEqual(videoItem?.keyEquivalent, "p")
        XCTAssertTrue(videoItem?.keyEquivalentModifierMask.contains(.option) ?? false)
        XCTAssertFalse(videoItem?.keyEquivalentModifierMask.contains(.command) ?? true)
    }

    @MainActor
    func testMenuIncludesAppearanceToggleShortcut() {
        let menu = StatusMenuBuilder.makeMenu(target: NSObject())

        let themeItem = menu.items.first { $0.title == "라이트/다크 전환" }

        XCTAssertNotNil(themeItem)
        XCTAssertEqual(themeItem?.action, Selector(("toggleAppearanceModeAction")))
        XCTAssertEqual(themeItem?.keyEquivalent, "d")
        XCTAssertTrue(themeItem?.keyEquivalentModifierMask.contains(.option) ?? false)
        XCTAssertTrue(themeItem?.keyEquivalentModifierMask.contains(.shift) ?? false)
    }

    @MainActor
    func testMenuOmitsInitialSetupAfterOnboardingOwnsThatFlow() {
        let menu = StatusMenuBuilder.makeMenu(target: NSObject())

        let setupItem = menu.items.first { $0.title == "초기 설정…" }
        let settingsItem = menu.items.first { $0.title == "설정…" }

        XCTAssertNil(setupItem)
        XCTAssertNotNil(settingsItem)
    }
}
