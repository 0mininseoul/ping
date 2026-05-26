import XCTest
@testable import Ping

@MainActor
final class HistoryViewModelTests: XCTestCase {
    func test_groupByDay_buildsDateHeaders() {
        let cal = Calendar(identifier: .gregorian)
        let today = Date()
        let yesterday = cal.date(byAdding: .day, value: -1, to: today)!

        let msgs: [VideoMessage] = [
            makeMsg(id: "m1", createdAt: today),
            makeMsg(id: "m2", createdAt: today),
            makeMsg(id: "m3", createdAt: yesterday)
        ]

        let groups = HistoryViewModel.groupByDay(messages: msgs, calendar: cal)
        XCTAssertEqual(groups.count, 2)
        // ascending: yesterday group first, today group last
        XCTAssertEqual(groups[0].messages.map(\.id), ["m3"])
        XCTAssertEqual(groups[1].messages.map(\.id), ["m1", "m2"])
    }

    func test_mergeTimeline_interleavesByTimestamp() {
        let cal = Calendar(identifier: .gregorian)
        let today = Date()

        let video = VideoMessage(
            id: "v1", roomId: "r", senderUid: "u",
            receiverUid: "rcv", senderNickname: "n",
            videoId: "v", videoUrl: "u/v.mp4", durationMs: 3000,
            mirrorPosition: MirrorPosition(xRatio: 0.5, yRatio: 0.5),
            status: .uploaded,
            createdAt: today,
            expiresAt: today.addingTimeInterval(60),
            captureMode: .faceOnly,
            aspectRatio: nil
        )
        let chat = ChatMessage(
            id: "c1", roomId: "r", senderUid: "u",
            senderNickname: "n", body: "hi",
            createdAt: today.addingTimeInterval(10)
        )

        let groups = HistoryViewModel.groupTimelineByDay(
            videos: [video],
            chats: [chat],
            calendar: cal
        )
        XCTAssertEqual(groups.count, 1)
        // ascending: video (today) first, chat (today+10s) last
        XCTAssertEqual(groups[0].items.map(\.id), ["video:v1", "chat:c1"])
    }

    func test_deleteVideoClearsExpandedScreenFaceOverlayState() throws {
        let source = try readProjectSource("Ping/UI/History/HistoryViewModel.swift")
        let deleteBody = try extract(
            "func delete(message: VideoMessage, currentUid: String?) async",
            through: "groups = Self.groupTimelineByDay(videos: loadedVideos, chats: loadedChats, calendar: .current)",
            from: source
        )

        XCTAssertTrue(deleteBody.contains("if expandedMessageId == id"))
        XCTAssertTrue(deleteBody.contains("expandedMessageId = nil"))
        XCTAssertTrue(deleteBody.contains("loadedVideos.removeAll { $0.videoUrl == message.videoUrl }"))
    }

    private func makeMsg(id: String, createdAt: Date) -> VideoMessage {
        VideoMessage(
            id: id,
            roomId: "r",
            senderUid: "u",
            receiverUid: "r",
            senderNickname: "nick",
            videoId: "v",
            videoUrl: "u/v.mp4",
            durationMs: 3000,
            mirrorPosition: MirrorPosition(xRatio: 0.5, yRatio: 0.5),
            status: .uploaded,
            createdAt: createdAt,
            expiresAt: createdAt.addingTimeInterval(60),
            captureMode: .faceOnly,
            aspectRatio: nil
        )
    }

    private func readProjectSource(_ relativePath: String) throws -> String {
        let testsDir = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
        let projectRoot = testsDir.deletingLastPathComponent()
        let fileURL = projectRoot.appendingPathComponent(relativePath)

        return try String(contentsOf: fileURL, encoding: .utf8)
    }

    private func extract(_ start: String, through end: String, from contents: String) throws -> String {
        let startRange = try XCTUnwrap(contents.range(of: start))
        let tail = contents[startRange.lowerBound...]
        let endRange = try XCTUnwrap(tail.range(of: end))
        return String(tail[..<endRange.upperBound])
    }
}
