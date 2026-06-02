import XCTest

final class PingMobileThreadInteractionsContractTests: XCTestCase {
    func testPingKitExposesReplyAndReactionContractsForMobileThread() throws {
        let service = try readProjectSource("PingKit/Sources/PingKit/PingService.swift")
        let models = try readProjectSource("PingKit/Sources/PingKit/PingRoomModels.swift")

        XCTAssertTrue(service.contains("reply_chat_uuid"))
        XCTAssertTrue(service.contains("reply_video_uuid"))
        XCTAssertTrue(service.contains("ping_react"))
        XCTAssertTrue(service.contains("ping_message_reactions"))
        XCTAssertTrue(models.contains("replyToChatId"))
        XCTAssertTrue(models.contains("replyToVideoId"))
        XCTAssertTrue(models.contains("PingMessageReaction"))
    }

    func testThreadViewShowsReplyPreviewsAndSendsReplyTarget() throws {
        let source = try readProjectSource("PingMobile/ThreadView.swift")

        XCTAssertTrue(source.contains("@State private var replyTarget"))
        XCTAssertTrue(source.contains("ReplyTarget"))
        XCTAssertTrue(source.contains("replyPreview(for:"))
        XCTAssertTrue(source.contains("quotedReplyPreview"))
        XCTAssertTrue(source.contains("sendChat(roomId: roomId, body: text, replyToChatId: replyChatId, replyToVideoId: replyVideoId)"))
    }

    func testThreadViewSupportsEmojiReactionContextMenuAndStrip() throws {
        let source = try readProjectSource("PingMobile/ThreadView.swift")

        XCTAssertTrue(source.contains("quickReactionEmojis"))
        XCTAssertTrue(source.contains("reactionsByTargetId"))
        XCTAssertTrue(source.contains("reactionStrip"))
        XCTAssertTrue(source.contains("toggleReaction(target:"))
        XCTAssertTrue(source.contains("refreshReactions()"))
    }

    private func readProjectSource(_ relativePath: String) throws -> String {
        let testsDir = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
        let projectRoot = testsDir.deletingLastPathComponent()
        return try String(contentsOf: projectRoot.appendingPathComponent(relativePath), encoding: .utf8)
    }
}
