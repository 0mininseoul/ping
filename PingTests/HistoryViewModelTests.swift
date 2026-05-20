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
        XCTAssertEqual(groups[0].messages.map(\.id), ["m1", "m2"])
        XCTAssertEqual(groups[1].messages.map(\.id), ["m3"])
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
}
