import XCTest
@testable import Ping

final class LinkPreviewContractTests: XCTestCase {
    func testFirstURLDetectsPlainHTTPSAndTrimsTrailingPunctuation() {
        let url = LinkPreviewDetector.firstURL(in: "이거 봐 https://example.com/path?x=1).")

        XCTAssertEqual(url?.absoluteString, "https://example.com/path?x=1")
    }

    func testFirstURLNormalizesBareWWWLink() {
        let url = LinkPreviewDetector.firstURL(in: "www.example.com/ping")

        XCTAssertEqual(url?.absoluteString, "https://www.example.com/ping")
    }

    func testOpenGraphParserExtractsTitleDescriptionAndImage() {
        let html = """
        <html><head>
        <meta property="og:title" content="Ping launch">
        <meta property="og:description" content="Three second video messages">
        <meta property="og:image" content="/card.png">
        </head></html>
        """

        let metadata = OpenGraphParser.parse(html: html, pageURL: URL(string: "https://example.com/post")!)

        XCTAssertEqual(metadata.title, "Ping launch")
        XCTAssertEqual(metadata.summary, "Three second video messages")
        XCTAssertEqual(metadata.imageURL?.absoluteString, "https://example.com/card.png")
    }

    func testMacChatRowRendersClickableLinkPreviewCard() throws {
        let source = try readProjectSource("Ping/UI/History/ChatMessageRowView.swift")

        XCTAssertTrue(source.contains("LinkPreviewCard(url:"))
        XCTAssertTrue(source.contains("LinkPreviewDetector.firstURL(in: message.body)"))
        XCTAssertTrue(source.contains("NSWorkspace.shared.open"))
    }

    func testSelectableTextMarksDetectedLinksAsClickableAttributes() throws {
        let source = try readProjectSource("Ping/UI/History/SelectableTextView.swift")

        XCTAssertTrue(source.contains(".link: match.url"))
        XCTAssertTrue(source.contains("NSWorkspace.shared.open(url)"))
    }

    func testIOSChatRowRendersLinkPreviewCardWithOpenURL() throws {
        let threadSource = try readProjectSource("PingMobile/ThreadView.swift")
        let cardSource = try readProjectSource("PingMobile/LinkPreviewCard.swift")

        XCTAssertTrue(threadSource.contains("LinkPreviewCard(url:"))
        XCTAssertTrue(threadSource.contains("PingLinkPreviewDetector.firstURL(in: chat.body)"))
        XCTAssertTrue(cardSource.contains("@Environment(\\.openURL)"))
        XCTAssertTrue(cardSource.contains("openURL(url)"))
    }

    private func readProjectSource(_ relativePath: String) throws -> String {
        let testsDir = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
        let projectRoot = testsDir.deletingLastPathComponent()
        return try String(contentsOf: projectRoot.appendingPathComponent(relativePath), encoding: .utf8)
    }
}
