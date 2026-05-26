import XCTest

final class ReactionPersistenceContractTests: XCTestCase {
    func testMessageReactionsPersistRealtimeMetadataForRoomHistoryRefresh() throws {
        let migration = try readSourceFile("20260526093431_reaction_realtime_metadata.sql")

        XCTAssertTrue(migration.contains("alter table public.message_reactions"))
        XCTAssertTrue(migration.contains("add column if not exists room_id uuid"))
        XCTAssertTrue(migration.contains("add column if not exists target_kind text"))
        XCTAssertTrue(migration.contains("add column if not exists target_id uuid"))
        XCTAssertTrue(migration.contains("create or replace function public.ping_fill_message_reaction_metadata"))
        XCTAssertTrue(migration.contains("before insert or update on public.message_reactions"))
        XCTAssertTrue(migration.contains("select cm.room_id, 'chat'::text, new.chat_message_id"))
        XCTAssertTrue(migration.contains("select m.room_id, 'video'::text, new.video_message_id"))
        XCTAssertTrue(migration.contains("update public.message_reactions mr"))
        XCTAssertTrue(migration.contains("alter table public.message_reactions alter column room_id set not null"))
        XCTAssertTrue(migration.contains("alter table public.message_reactions replica identity full"))
        XCTAssertTrue(migration.contains("alter publication supabase_realtime add table public.message_reactions"))
    }

    func testReactionMetadataTriggerIsPrivateAndRealtimePublicationIsRequired() throws {
        let migration = try readSourceFile("20260526120003_reaction_metadata_hardening.sql")

        XCTAssertTrue(migration.contains("revoke all on function public.ping_fill_message_reaction_metadata()"))
        XCTAssertTrue(migration.contains("from public, anon, authenticated"))
        XCTAssertTrue(migration.contains("alter publication supabase_realtime add table public.message_reactions"))
        XCTAssertTrue(migration.contains("pg_publication_tables"))
        XCTAssertTrue(migration.contains("raise exception 'message_reactions must be in supabase_realtime publication'"))
    }

    private func readSourceFile(_ relativePath: String) throws -> String {
        let fileName = URL(fileURLWithPath: relativePath).lastPathComponent
        let fileURL = try XCTUnwrap(Bundle(for: Self.self).resourceURL?.appendingPathComponent(fileName))
        return try String(contentsOf: fileURL, encoding: .utf8)
    }
}
