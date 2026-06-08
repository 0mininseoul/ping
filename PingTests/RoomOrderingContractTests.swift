import XCTest

final class RoomOrderingContractTests: XCTestCase {
    func testBackendRoomsExposeManualOrderAndUnreadPriority() throws {
        let migration = try readSourceFile("supabase/migrations/20260607161110_room_order_unread_badges.sql")

        XCTAssertTrue(migration.contains("add column if not exists room_order"))
        XCTAssertTrue(migration.contains("create or replace function public.ping_reorder_my_rooms"))
        XCTAssertTrue(migration.contains("room_ids uuid[]"))
        XCTAssertTrue(migration.contains("create or replace function public.ping_my_rooms()"))
        XCTAssertTrue(migration.contains("room_order integer"))
        XCTAssertTrue(migration.contains("unread_count integer"))
        XCTAssertTrue(migration.contains("latest_unread_at timestamptz"))
        XCTAssertTrue(migration.contains("coalesce(chat_unread.unread_count, 0) + coalesce(video_unread.unread_count, 0)"))
        XCTAssertTrue(migration.contains("coalesce(chat_unread.latest_unread_at, video_unread.latest_unread_at)"))
        XCTAssertTrue(migration.contains("order by (coalesce(chat_unread.unread_count, 0) + coalesce(video_unread.unread_count, 0) > 0) desc"))
    }

    func testMarkRoomReadClearsChatAndVideoUnreadState() throws {
        let migrations = try readSupabaseMigrationSources()
        guard let start = migrations.range(
            of: "create or replace function public.ping_mark_room_read",
            options: .backwards
        ) else {
            return XCTFail("ping_mark_room_read RPC is missing")
        }
        let functionSource = String(migrations[start.lowerBound...])

        XCTAssertTrue(functionSource.contains("last_read_chat_at"))
        XCTAssertTrue(functionSource.contains("update public.messages"))
        XCTAssertTrue(functionSource.contains("set status = 'seen'"))
        XCTAssertTrue(functionSource.contains("receiver_uid = me"))
        XCTAssertTrue(functionSource.contains("room_id = room_uuid"))
        XCTAssertTrue(functionSource.contains("status = 'uploaded'"))
    }

    func testIncomingVideoNotificationsIgnoreMessagesAlreadyReadByRoomTimestamp() throws {
        let migrations = try readSupabaseMigrationSources()
        guard let start = migrations.range(
            of: "create or replace function public.ping_incoming_messages()",
            options: .backwards
        ) else {
            return XCTFail("ping_incoming_messages RPC is missing")
        }
        let functionSource = String(migrations[start.lowerBound...])

        XCTAssertTrue(functionSource.contains("last_read_chat_at"))
        XCTAssertTrue(functionSource.contains("read_map"))
        XCTAssertTrue(functionSource.contains("read_map ->> m.room_id::text"))
        XCTAssertTrue(functionSource.contains("m.created_at > coalesce"))
    }

    func testSharedRoomModelsDecodeOrderAndUnreadMetadata() throws {
        let macModels = try readSourceFile("Ping/Core/Models.swift")
        let pingKitModels = try readSourceFile("PingKit/Sources/PingKit/PingRoomModels.swift")
        let windowsRoom = try readSourceFile("windows/src/Ping.Windows.Core/Models/Room.cs")

        for source in [macModels, pingKitModels] {
            XCTAssertTrue(source.contains("roomOrder"))
            XCTAssertTrue(source.contains("unreadCount"))
            XCTAssertTrue(source.contains("latestUnreadAt"))
            XCTAssertTrue(source.contains("roomOrder = \"room_order\""))
            XCTAssertTrue(source.contains("unreadCount = \"unread_count\""))
            XCTAssertTrue(source.contains("latestUnreadAt = \"latest_unread_at\""))
        }

        XCTAssertTrue(windowsRoom.contains("JsonPropertyName(\"room_order\")"))
        XCTAssertTrue(windowsRoom.contains("int? RoomOrder"))
        XCTAssertTrue(windowsRoom.contains("JsonPropertyName(\"unread_count\")"))
        XCTAssertTrue(windowsRoom.contains("int UnreadCount"))
        XCTAssertTrue(windowsRoom.contains("JsonPropertyName(\"latest_unread_at\")"))
        XCTAssertTrue(windowsRoom.contains("DateTimeOffset? LatestUnreadAt"))
    }

    func testRoomServicesExposeReorderRpcAcrossClients() throws {
        let macService = try readSourceFile("Ping/Backend/RoomService.swift")
        let pingKitService = try readSourceFile("PingKit/Sources/PingKit/PingService.swift")
        let windowsService = try readSourceFile("windows/src/Ping.Windows.Core/Backend/RoomService.cs")

        XCTAssertTrue(macService.contains("func reorderRooms(roomIds: [String]) async throws"))
        XCTAssertTrue(macService.contains("\"ping_reorder_my_rooms\""))
        XCTAssertTrue(macService.contains("\"room_ids\": roomIds"))

        XCTAssertTrue(pingKitService.contains("func reorderMyRooms(roomIds: [String]) async throws"))
        XCTAssertTrue(pingKitService.contains("\"ping_reorder_my_rooms\""))
        XCTAssertTrue(pingKitService.contains("\"room_ids\": roomIds"))

        XCTAssertTrue(windowsService.contains("ReorderMyRoomsAsync"))
        XCTAssertTrue(windowsService.contains("\"ping_reorder_my_rooms\""))
        XCTAssertTrue(windowsService.contains("RoomIdsRpcBody"))
    }

    func testRoomListsSupportManualReorderAndUnreadBadgesAcrossPlatforms() throws {
        let inbox = try readSourceFile("PingMobile/InboxView.swift")
        let roomManager = try readSourceFile("Ping/UI/Setup/RoomManagerWindow.swift")
        let historySidebar = try readSourceFile("Ping/UI/History/HistorySidebar.swift")
        let windowsViewModel = try readSourceFile("windows/src/Ping.Windows.App/Setup/RoomManagerViewModel.cs")
        let windowsXaml = try readSourceFile("windows/src/Ping.Windows.App/Setup/RoomManagerWindow.xaml")

        XCTAssertTrue(inbox.contains(".onMove(perform: moveRooms)"))
        XCTAssertTrue(inbox.contains("UnreadRoomBadge(count: room.unreadCount)"))
        XCTAssertTrue(inbox.contains("client.reorderMyRooms(roomIds: orderedRoomIds)"))

        XCTAssertTrue(roomManager.contains(".onMove(perform: moveRooms)"))
        XCTAssertTrue(roomManager.contains("UnreadRoomBadge(count: room.unreadCount)"))
        XCTAssertTrue(roomManager.contains("try await roomService.reorderRooms(roomIds: orderedRoomIds)"))

        XCTAssertTrue(historySidebar.contains("UnreadRoomBadge(count: room.unreadCount)"))

        XCTAssertTrue(windowsViewModel.contains("MoveSelectedRoomAsync"))
        XCTAssertTrue(windowsViewModel.contains("await roomService.ReorderMyRoomsAsync"))
        XCTAssertTrue(windowsXaml.contains("MoveUpRoomButton_Click"))
        XCTAssertTrue(windowsXaml.contains("MoveDownRoomButton_Click"))
        XCTAssertTrue(windowsXaml.contains("UnreadCount"))
    }

    func testOpeningRoomClearsLocalUnreadBadgeAcrossDesktopClients() throws {
        let macAppState = try readSourceFile("Ping/Core/AppState.swift")
        let macHistoryViewModel = try readSourceFile("Ping/UI/History/HistoryViewModel.swift")
        let windowsHistoryViewModel = try readSourceFile("windows/src/Ping.Windows.App/History/HistoryViewModel.cs")

        XCTAssertTrue(macAppState.contains("func markRoomReadLocally(roomId: String)"))
        XCTAssertTrue(macAppState.contains("unreadCount = 0"))
        XCTAssertTrue(macAppState.contains("latestUnreadAt = nil"))
        XCTAssertTrue(macHistoryViewModel.contains("appState.markRoomReadLocally(roomId: roomId)"))

        XCTAssertTrue(windowsHistoryViewModel.contains("ClearSelectedRoomUnreadBadge(roomId)"))
        XCTAssertTrue(windowsHistoryViewModel.contains("UnreadCount = 0"))
        XCTAssertTrue(windowsHistoryViewModel.contains("LatestUnreadAt = null"))
    }

    private func readSourceFile(_ relativePath: String) throws -> String {
        let testsDir = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
        let projectRoot = testsDir.deletingLastPathComponent()
        return try String(contentsOf: projectRoot.appendingPathComponent(relativePath), encoding: .utf8)
    }

    private func readSupabaseMigrationSources() throws -> String {
        let testsDir = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
        let projectRoot = testsDir.deletingLastPathComponent()
        let migrationsURL = projectRoot.appendingPathComponent("supabase/migrations")
        let migrationFiles = try FileManager.default.contentsOfDirectory(
            at: migrationsURL,
            includingPropertiesForKeys: nil
        )
        .filter { $0.pathExtension == "sql" }
        .sorted { $0.lastPathComponent < $1.lastPathComponent }

        return try migrationFiles
            .map { try String(contentsOf: $0, encoding: .utf8) }
            .joined(separator: "\n")
    }
}
