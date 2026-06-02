import XCTest

final class CanonicalRoomNameContractTests: XCTestCase {
    func testSupabaseMigrationPreservesCustomNamesAndRefreshesAutomaticNames() throws {
        let migration = try readProjectSource("supabase/migrations/20260602093214_canonical_room_names.sql")

        XCTAssertTrue(migration.contains("name_is_custom boolean not null default false"))
        XCTAssertTrue(migration.contains("ping_private.room_default_name"))
        XCTAssertTrue(migration.contains("string_agg(nullif(trim(rm.nickname), ''), ', ' order by rm.created_at, rm.user_id::text)"))
        XCTAssertTrue(migration.contains("ping_private.refresh_room_auto_name"))
        XCTAssertTrue(migration.contains("and r_update.name_is_custom = false"))
        XCTAssertTrue(migration.contains("name_is_custom = true"))
    }

    func testRoomMemberChangesRefreshOnlyAutomaticNames() throws {
        let migration = try readProjectSource("supabase/migrations/20260602093214_canonical_room_names.sql")

        XCTAssertTrue(migration.contains("perform ping_private.refresh_room_auto_name(room_uuid);"))
        XCTAssertTrue(migration.contains("perform ping_private.refresh_room_auto_name(invitation_row.room_id);"))
        XCTAssertTrue(migration.contains("perform ping_private.refresh_room_auto_name(link_row.room_id);"))
        XCTAssertTrue(migration.contains("perform ping_private.refresh_room_auto_name(new_room_id);"))
        XCTAssertTrue(migration.contains("for room_to_refresh in"))
    }

    func testRoomSearchNormalizationMatchesClientWhitespaceRemoval() throws {
        let migration = try readProjectSource("supabase/migrations/20260602094828_canonical_room_searchable_names.sql")

        XCTAssertTrue(migration.contains("regexp_replace(trim(coalesce(name_text, '')), '\\s+', '', 'g')"))
        XCTAssertTrue(migration.contains("where r_update.name_is_custom = false"))
    }

    func testMobileThreadTitleUsesRoomNameInsteadOfSenderNicknames() throws {
        let routeSource = try readProjectSource("PingMobile/AppEnvironment.swift")
        let contentSource = try readProjectSource("PingMobile/ContentView.swift")
        let inboxSource = try readProjectSource("PingMobile/InboxView.swift")
        let threadSource = try readProjectSource("PingMobile/ThreadView.swift")

        XCTAssertTrue(routeSource.contains("case thread(roomId: String, roomName: String?)"))
        XCTAssertTrue(contentSource.contains("ThreadView(account: paired, roomId: roomId, roomName: roomName)"))
        XCTAssertTrue(inboxSource.contains("PingRoute.thread(roomId: room.id, roomName: room.name)"))
        XCTAssertTrue(threadSource.contains("init(account: PairedAccount, roomId: String, roomName: String?)"))
        XCTAssertTrue(threadSource.contains(".navigationTitle(roomName)"))
        XCTAssertFalse(threadSource.contains("private var title: String"))
        XCTAssertFalse(threadSource.contains("return m.senderNickname"))
        XCTAssertFalse(threadSource.contains("return c.senderNickname"))
    }

    func testSharedRoomTitleDocumentsCanonicalServerName() throws {
        let source = try readProjectSource("PingKit/Sources/PingKit/PingRoomModels.swift")

        XCTAssertTrue(source.contains("public var displayTitle: String { name }"))
        XCTAssertTrue(source.contains("public func title(excluding myUid: String) -> String {"))
        XCTAssertTrue(source.contains("return name"))
    }

    private func readProjectSource(_ relativePath: String) throws -> String {
        let testsDir = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
        let projectRoot = testsDir.deletingLastPathComponent()
        return try String(contentsOf: projectRoot.appendingPathComponent(relativePath), encoding: .utf8)
    }
}
