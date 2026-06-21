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

    func testLongURLWrapsWithinTextContentWidth() {
        let font = NSFont.systemFont(ofSize: NSFont.systemFontSize)
        let text = "그리고 애들아 이거 한번 가입해서 써봐\nhttps://gatitagachon.vercel.app/invite/abcdefghijklmnopqrstuvwxyz"

        let size = SelectableTextLayout.size(text: text, font: font, maxWidth: 258, proposedWidth: nil)

        XCTAssertLessThanOrEqual(size.width, 258)
        XCTAssertGreaterThan(size.height, 40)
    }

    func testLongURLChatBubbleOuterWidthFitsMessageColumn() {
        let font = NSFont.systemFont(ofSize: NSFont.systemFontSize)
        let text = "그리고 애들아 이거 한번 가입해서 써봐\nhttps://gatitagachon.vercel.app/invite/abcdefghijklmnopqrstuvwxyz"

        let size = ChatMessageBubbleLayout.textContentSize(for: text, font: font)
        let outerWidth = size.width + ChatMessageBubbleLayout.textBubbleHorizontalPadding * 2

        XCTAssertLessThanOrEqual(size.width, ChatMessageBubbleLayout.textContentMaxWidth)
        XCTAssertLessThanOrEqual(outerWidth, ChatMessageBubbleLayout.messageMaxWidth)
        XCTAssertGreaterThan(size.height, 40)
    }
}
