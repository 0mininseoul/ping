import Foundation
import Testing
@testable import PingKit

@Suite struct LinkPreviewTests {
    @Test func firstURLDetectsHTTPSAndBareWWWLinks() throws {
        #expect(PingLinkPreviewDetector.firstURL(in: "봐 https://example.com/a).")?.absoluteString == "https://example.com/a")
        #expect(PingLinkPreviewDetector.firstURL(in: "www.example.com/ping")?.absoluteString == "https://www.example.com/ping")
    }

    @Test func openGraphParserExtractsCardMetadata() throws {
        let html = """
        <html><head>
        <title>Fallback title</title>
        <meta property="og:title" content="OG title">
        <meta name="description" content="Meta description">
        <meta property="og:image" content="/og.png">
        </head></html>
        """

        let metadata = PingOpenGraphParser.parse(html: html, pageURL: URL(string: "https://example.com/post")!)

        #expect(metadata.title == "OG title")
        #expect(metadata.summary == "Meta description")
        #expect(metadata.imageURL?.absoluteString == "https://example.com/og.png")
    }
}
