import AppKit
import XCTest
@testable import Ping

@MainActor
final class SelectableTextLayoutTests: XCTestCase {
    func testShortChatTextKeepsIntrinsicBubbleWidth() {
        let font = NSFont.systemFont(ofSize: NSFont.systemFontSize)
        let size = SelectableTextLayout.size(text: "ㅋㅋ", font: font, maxWidth: 280, proposedWidth: nil)

        XCTAssertLessThan(size.width, 80)
        XCTAssertGreaterThan(size.width, 8)
    }

    func testLongChatTextWrapsAtMaximumWidth() {
        let font = NSFont.systemFont(ofSize: NSFont.systemFontSize)
        let short = SelectableTextLayout.size(text: "짧은 말", font: font, maxWidth: 280, proposedWidth: nil)
        let long = SelectableTextLayout.size(
            text: String(repeating: "긴 메시지입니다 ", count: 24),
            font: font,
            maxWidth: 280,
            proposedWidth: nil
        )

        XCTAssertLessThanOrEqual(long.width, 280)
        XCTAssertGreaterThan(long.width, short.width)
        XCTAssertGreaterThan(long.height, short.height * 2)
    }
}
