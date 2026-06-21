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

    func testFirstURLDetectsGatiGachonLinkInKoreanSentence() {
        let text = "그리고 애들아 이거 한번 가입해서 써봐\nhttps://gatitagachon.vercel.app/"

        let url = LinkPreviewDetector.firstURL(in: text)

        XCTAssertEqual(url?.absoluteString, "https://gatitagachon.vercel.app/")
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

    func testOpenGraphParserExtractsGatiGachonMetadata() {
        let html = """
        <!DOCTYPE html><html lang="ko"><head>
        <title>같이타 - 가천대 통학 동행 플랫폼</title>
        <meta name="description" content="가천대학교 학생들을 위한 통학 경로 동행자 매칭 서비스입니다.">
        <meta property="og:title" content="같이타 : 가천대 통학 동행 플랫폼"/>
        <meta property="og:description" content="가천대역에서 AI공학관까지, 안전하고 편리하게 함께 이동하세요!"/>
        <meta property="og:image" content="https://gatitagachon.vercel.app/og-image.png"/>
        <meta name="twitter:image" content="https://gatitagachon.vercel.app/twitter.png"/>
        </head></html>
        """

        let metadata = OpenGraphParser.parse(html: html, pageURL: URL(string: "https://gatitagachon.vercel.app/")!)

        XCTAssertEqual(metadata.title, "같이타 : 가천대 통학 동행 플랫폼")
        XCTAssertEqual(metadata.summary, "가천대역에서 AI공학관까지, 안전하고 편리하게 함께 이동하세요!")
        XCTAssertEqual(metadata.imageURL?.absoluteString, "https://gatitagachon.vercel.app/og-image.png")
    }

    func testYouTubeFallbackProvidesStableThumbnailAndSiteName() {
        let url = URL(string: "https://www.youtube.com/watch?v=oFAvC8gw-fQ")!

        let metadata = LinkPreviewMetadata.fallback(url: url)

        XCTAssertEqual(metadata.displayTitle, "YouTube")
        XCTAssertEqual(metadata.siteName, "YouTube")
        XCTAssertEqual(metadata.imageURL?.absoluteString, "https://i.ytimg.com/vi/oFAvC8gw-fQ/hqdefault.jpg")
    }

    func testOpenGraphParserUsesYouTubeThumbnailWhenImageMetaIsMissing() {
        let html = """
        <html><head>
        <meta property="og:title" content="COMEUP 2023">
        <meta property="og:site_name" content="YouTube">
        </head></html>
        """

        let metadata = OpenGraphParser.parse(html: html, pageURL: URL(string: "https://youtu.be/oFAvC8gw-fQ")!)

        XCTAssertEqual(metadata.title, "COMEUP 2023")
        XCTAssertEqual(metadata.siteName, "YouTube")
        XCTAssertEqual(metadata.imageURL?.absoluteString, "https://i.ytimg.com/vi/oFAvC8gw-fQ/hqdefault.jpg")
    }

    func testMacChatRowRendersClickableLinkPreviewCard() throws {
        let source = try readProjectSource("Ping/UI/History/ChatMessageRowView.swift")

        XCTAssertTrue(source.contains("LinkPreviewCard(url:"))
        XCTAssertTrue(source.contains("LinkPreviewDetector.firstURL(in: message.body)"))
        XCTAssertTrue(source.contains("NSWorkspace.shared.open"))
        XCTAssertTrue(source.contains("messageMaxWidth - textBubbleHorizontalPadding * 2"))
        XCTAssertTrue(source.contains(".frame(width: textSize.width, height: textSize.height"))
        XCTAssertTrue(source.contains(".frame(maxWidth: .infinity, alignment: isMine ? .trailing : .leading)"))
    }

    func testMacTimelineRowsResolveToFullWidthBeforeTrailingAlignment() throws {
        let source = try readProjectSource("Ping/UI/History/RoomTimelineView.swift")
        let timelineRow = try sourceSlice(
            in: source,
            from: "private func timelineRow(for item: TimelineItem) -> some View",
            to: "@ViewBuilder\n    private func timestampLabel"
        )

        XCTAssertTrue(timelineRow.contains("ZStack(alignment: .trailing)"))
        XCTAssertTrue(timelineRow.contains(".frame(maxWidth: .infinity, alignment: .trailing)"))
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

    func testLinkPreviewCardsUseCompactVerticalImageLayout() throws {
        let macCardSource = try readProjectSource("Ping/UI/History/LinkPreviewCard.swift")
        let iosCardSource = try readProjectSource("PingMobile/LinkPreviewCard.swift")

        XCTAssertTrue(macCardSource.contains("private let cardWidth: CGFloat = 248"))
        XCTAssertTrue(macCardSource.contains("private let previewImageHeight: CGFloat = 124"))
        XCTAssertTrue(macCardSource.contains(".padding(.trailing, isMine ? 28 : 0)"))
        XCTAssertTrue(macCardSource.contains("metadataText"))
        XCTAssertFalse(macCardSource.contains(".frame(width: 54, height: 54)"))

        XCTAssertTrue(iosCardSource.contains("private let maxCardWidth: CGFloat = 300"))
        XCTAssertTrue(iosCardSource.contains("private let horizontalSafetyInset: CGFloat = 112"))
        XCTAssertTrue(iosCardSource.contains("private let previewImageHeight: CGFloat = 132"))
        XCTAssertTrue(iosCardSource.contains("metadataText"))
        XCTAssertFalse(iosCardSource.contains(".frame(width: 54, height: 54)"))
    }

    func testLinkPreviewFetchFailuresAreNotPersistedAsMetadata() throws {
        let macCacheSource = try readProjectSource("Ping/Core/LinkPreview.swift")
        let kitCacheSource = try readProjectSource("PingKit/Sources/PingKit/LinkPreviewSupport.swift")

        XCTAssertTrue(macCacheSource.contains("metadataByURL[url] = metadata\n            return metadata"))
        XCTAssertTrue(macCacheSource.contains("return .fallback(url: url)"))

        XCTAssertTrue(kitCacheSource.contains("metadataByURL[url] = metadata\n            return metadata"))
        XCTAssertTrue(kitCacheSource.contains("return .fallback(url: url)"))
    }

    private func readProjectSource(_ relativePath: String) throws -> String {
        let testsDir = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
        let projectRoot = testsDir.deletingLastPathComponent()
        return try String(contentsOf: projectRoot.appendingPathComponent(relativePath), encoding: .utf8)
    }

    private func sourceSlice(in source: String, from start: String, to end: String) throws -> String {
        guard let startRange = source.range(of: start),
              let endRange = source.range(of: end, range: startRange.upperBound..<source.endIndex) else {
            throw XCTSkip("source markers not found")
        }
        return String(source[startRange.lowerBound..<endRange.lowerBound])
    }
}
