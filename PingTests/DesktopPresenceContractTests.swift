import XCTest

final class DesktopPresenceContractTests: XCTestCase {
    func testBackendDefinesDesktopPresenceHeartbeatContract() throws {
        let migration = try readSourceFile("supabase/migrations/20260701000100_desktop_presence.sql")

        XCTAssertTrue(migration.contains("create table if not exists public.desktop_presence"))
        XCTAssertTrue(migration.contains("primary key (uid, device_id)"))
        XCTAssertTrue(migration.contains("active_room_id uuid"))
        XCTAssertTrue(migration.contains("create or replace function public.ping_update_desktop_presence"))
        XCTAssertTrue(migration.contains("create or replace function public.ping_clear_desktop_presence"))
    }

    func testMacAppPublishesDesktopPresenceHeartbeat() throws {
        let service = try readSourceFile("Ping/Backend/DesktopPresenceService.swift")
        let appDelegate = try readSourceFile("Ping/AppDelegate.swift")

        XCTAssertTrue(service.contains("ping_update_desktop_presence"))
        XCTAssertTrue(service.contains("ping_clear_desktop_presence"))
        XCTAssertTrue(service.contains("active_room_uuid"))
        XCTAssertTrue(appDelegate.contains("private let desktopPresenceService = DesktopPresenceService()"))
        XCTAssertTrue(appDelegate.contains("startDesktopPresenceHeartbeat()"))
        XCTAssertTrue(appDelegate.contains("desktopPresenceTask?.cancel()"))
    }

    func testPushSuppressesMobileWhenDesktopPresenceIsFresh() throws {
        let push = try readSourceFile("api/push.ts")

        XCTAssertTrue(push.contains("freshDesktopPresenceUids"))
        XCTAssertTrue(push.contains(".from('desktop_presence')"))
        XCTAssertTrue(push.contains("PUSH_DESKTOP_PRESENCE_TTL_SECONDS"))
        XCTAssertTrue(push.contains("suppressed"))
    }

    func testSelectedRealtimeChatIsMarkedReadAgain() throws {
        let source = try readSourceFile("Ping/UI/History/HistoryViewModel.swift")
        let chatService = try readSourceFile("Ping/Backend/ChatMessageService.swift")

        XCTAssertTrue(source.contains("markSelectedRoomReadAfterRealtime(roomId: msg.roomId)"))
        XCTAssertTrue(source.contains("try await chatService.markRoomChatRead(roomId: roomId)"))
        XCTAssertTrue(chatService.contains("func markRoomChatRead(roomId: String) async throws"))
        XCTAssertTrue(chatService.contains("\"ping_mark_room_chat_read\""))
        XCTAssertTrue(source.contains("appState.markRoomReadLocally(roomId: roomId)"))
    }

    private func readSourceFile(_ relativePath: String) throws -> String {
        let testsDir = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
        let projectRoot = testsDir.deletingLastPathComponent()
        return try String(contentsOf: projectRoot.appendingPathComponent(relativePath), encoding: .utf8)
    }
}
