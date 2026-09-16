import XCTest
@testable import Ping

/// 보낸 메시지 "모두에게서 삭제"는 보낸 뒤 5분까지만. 메뉴(앱)와 거절(서버)이 같은 규칙이어야 한다 —
/// 앱만 막으면 구버전이 계속 지우고, 서버만 막으면 누를 수 있는 메뉴가 "삭제 실패"만 남긴다.
final class SentMessageDeletionContractTests: XCTestCase {
    private let migrationName = "20260916000100_sender_delete_window.sql"

    func testServerRejectsSenderVideoDeletionAfterTheWindow() throws {
        let body = try functionBody("ping_remove_video_message")

        let ownerBranch = try XCTUnwrap(body.range(of: "if owner_uid = me then"))
        let recipientBranch = try XCTUnwrap(body.range(of: "elsif recipient_uid = me then"))
        let owner = body[ownerBranch.upperBound..<recipientBranch.lowerBound]
        let recipient = body[recipientBranch.upperBound...]

        let windowCheck = try XCTUnwrap(owner.range(of: "interval '5 minutes'"))
        let delete = try XCTUnwrap(owner.range(of: "delete from public.messages"))
        XCTAssertLessThan(windowCheck.lowerBound, delete.lowerBound)
        XCTAssertTrue(owner.contains("delete_window_expired"))
        XCTAssertTrue(owner.contains("video_url = video_path"))

        // 받은 사람의 "나에게서 숨기기"는 보낸 메시지 삭제가 아니므로 시간 제한이 없다.
        XCTAssertFalse(recipient.contains("interval '5 minutes'"))
        XCTAssertTrue(recipient.contains("hidden_for_receiver = true"))

        // 운영 DB는 storage.objects 직접 삭제를 막는다. 넣으면 삭제 자체가 깨진다.
        XCTAssertFalse(body.contains("delete from storage.objects"))
    }

    func testServerRejectsSenderChatDeletionAfterTheWindow() throws {
        let body = try functionBody("ping_delete_chat")

        let senderCheck = try XCTUnwrap(body.range(of: "only sender can delete"))
        let windowCheck = try XCTUnwrap(body.range(of: "interval '5 minutes'"))
        let delete = try XCTUnwrap(body.range(of: "delete from public.chat_messages where id = chat_uuid"))
        XCTAssertLessThan(senderCheck.lowerBound, windowCheck.lowerBound)
        XCTAssertLessThan(windowCheck.lowerBound, delete.lowerBound)
        XCTAssertTrue(body.contains("delete_window_expired"))
        XCTAssertFalse(body.contains("delete from storage.objects"))
    }

    func testAppAndServerShareTheSameWindow() throws {
        XCTAssertEqual(SentMessageDeletionPolicy.window, 5 * 60)
        XCTAssertTrue(try readFixture(migrationName).contains("interval '5 minutes'"))
    }

    func testVideoDeleteMenuIsGatedByTheWindowOnlyForTheSender() throws {
        let source = try readFixture("RoomTimelineView.swift")

        XCTAssertTrue(source.contains(
            "canDelete: isMine ? SentMessageDeletionPolicy.canDelete(createdAt: v.createdAt, now: Date()) : v.receiverUid == myUid"
        ))
    }

    /// 텍스트 버블 메뉴는 우클릭하는 순간 만들어지므로 그때의 시각으로 판단해야 한다.
    func testChatDeleteMenuIsGatedByTheWindow() throws {
        let source = try readFixture("ChatMessageRowView.swift")

        XCTAssertTrue(source.contains("isMine && SentMessageDeletionPolicy.canDelete(createdAt: message.createdAt, now: Date())"))
        // 사진·링크 카드(SwiftUI 메뉴)와 텍스트 버블(NSMenu) 세 곳 모두.
        XCTAssertEqual(source.components(separatedBy: "if canDeleteNow {").count - 1, 3)
    }

    func testViewModelExplainsAnExpiredWindowInsteadOfAGenericFailure() throws {
        let source = try readFixture("HistoryViewModel.swift")

        XCTAssertTrue(source.contains("SentMessageDeletionPolicy.isWindowExpired(error)"))
        XCTAssertTrue(source.contains("SentMessageDeletionPolicy.expiredMessage"))
        XCTAssertTrue(source.contains("func deleteChat(_ message: ChatMessage) async"))
    }

    private func functionBody(_ name: String) throws -> Substring {
        let sql = try readFixture(migrationName)
        let start = try XCTUnwrap(sql.range(of: "create or replace function public.\(name)("))
        let end = try XCTUnwrap(sql.range(of: "grant execute on function public.\(name)(", range: start.upperBound..<sql.endIndex))
        return sql[start.lowerBound..<end.lowerBound]
    }

    private func readFixture(_ fileName: String) throws -> String {
        let fileURL = try XCTUnwrap(Bundle(for: Self.self).resourceURL?.appendingPathComponent(fileName))
        return try String(contentsOf: fileURL, encoding: .utf8)
    }
}
