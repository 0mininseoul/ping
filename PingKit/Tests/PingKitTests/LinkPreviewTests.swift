import Foundation
import Testing
@testable import PingKit

@Suite struct LinkPreviewTests {
    @Test func firstURLDetectsHTTPSAndBareWWWLinks() throws {
        #expect(PingLinkPreviewDetector.firstURL(in: "봐 https://example.com/a).")?.absoluteString == "https://example.com/a")
        #expect(PingLinkPreviewDetector.firstURL(in: "www.example.com/ping")?.absoluteString == "https://www.example.com/ping")
        #expect(PingLinkPreviewDetector.firstURL(in: "그리고 애들아 이거 한번 가입해서 써봐\nhttps://gatitagachon.vercel.app/")?.absoluteString == "https://gatitagachon.vercel.app/")
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

    @Test func openGraphParserExtractsGatiGachonMetadata() throws {
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

        let metadata = PingOpenGraphParser.parse(html: html, pageURL: URL(string: "https://gatitagachon.vercel.app/")!)

        #expect(metadata.title == "같이타 : 가천대 통학 동행 플랫폼")
        #expect(metadata.summary == "가천대역에서 AI공학관까지, 안전하고 편리하게 함께 이동하세요!")
        #expect(metadata.imageURL?.absoluteString == "https://gatitagachon.vercel.app/og-image.png")
    }

    @Test func youtubeFallbackProvidesStableThumbnailAndSiteName() throws {
        let metadata = PingLinkPreviewMetadata.fallback(url: URL(string: "https://www.youtube.com/watch?v=oFAvC8gw-fQ")!)

        #expect(metadata.displayTitle == "YouTube")
        #expect(metadata.siteName == "YouTube")
        #expect(metadata.imageURL?.absoluteString == "https://i.ytimg.com/vi/oFAvC8gw-fQ/hqdefault.jpg")
    }

    @Test func openGraphParserUsesYouTubeThumbnailWhenImageMetaIsMissing() throws {
        let html = """
        <html><head>
        <meta property="og:title" content="COMEUP 2023">
        <meta property="og:site_name" content="YouTube">
        </head></html>
        """

        let metadata = PingOpenGraphParser.parse(html: html, pageURL: URL(string: "https://youtu.be/oFAvC8gw-fQ")!)

        #expect(metadata.title == "COMEUP 2023")
        #expect(metadata.siteName == "YouTube")
        #expect(metadata.imageURL?.absoluteString == "https://i.ytimg.com/vi/oFAvC8gw-fQ/hqdefault.jpg")
    }
}
