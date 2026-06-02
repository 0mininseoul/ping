import XCTest

final class PingMobileImageAttachmentContractTests: XCTestCase {
    func testThreadViewRendersImageChatMessagesAsAttachments() throws {
        let source = try readProjectSource("PingMobile/ThreadView.swift")
        let chatRow = try extract(
            "private func chatRow",
            through: "// MARK: - Reply bar",
            from: source
        )

        XCTAssertTrue(chatRow.contains("if chat.hasImage"))
        XCTAssertTrue(chatRow.contains("ChatImageAttachmentView(message: chat)"))
        XCTAssertFalse(chatRow.contains("Text(chat.preview.isEmpty ? \" \" : chat.preview)"))
    }

    func testChatImageAttachmentViewDownloadsPrivateMediaObject() throws {
        let source = try readProjectSource("PingMobile/ChatImageAttachmentView.swift")

        XCTAssertTrue(source.contains("Image(uiImage: image)"))
        XCTAssertTrue(source.contains("downloadChatMedia(path: mediaPath)"))
        XCTAssertTrue(source.contains("message.mediaFileExtension"))
        XCTAssertTrue(source.contains("message.mediaWidth"))
        XCTAssertTrue(source.contains("message.mediaHeight"))
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
