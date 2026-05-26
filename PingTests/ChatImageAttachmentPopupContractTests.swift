import XCTest

final class ChatImageAttachmentPopupContractTests: XCTestCase {
    func testChatImageAttachmentOpensLargePreviewPopoverOnClick() throws {
        let source = try readProjectSource("Ping/UI/History/ChatImageAttachmentView.swift")

        XCTAssertTrue(source.contains("@State private var isPreviewPresented = false"))
        XCTAssertTrue(source.contains(".onTapGesture"))
        XCTAssertTrue(source.contains("isPreviewPresented = true"))
        XCTAssertTrue(source.contains(".popover(isPresented: $isPreviewPresented"))
        XCTAssertTrue(source.contains("ChatImagePreviewPopover"))
    }

    private func readProjectSource(_ relativePath: String) throws -> String {
        let testsDir = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
        let projectRoot = testsDir.deletingLastPathComponent()
        let fileURL = projectRoot.appendingPathComponent(relativePath)

        return try String(contentsOf: fileURL, encoding: .utf8)
    }
}
