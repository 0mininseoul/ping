import XCTest

final class StoragePolicyContractTests: XCTestCase {
    func testRoomMemberStorageReadPolicyAllowsSeenVideoMessages() throws {
        let baselinePolicy = try readSourceFile("20260523000500_storage_read_room_member.sql")
        let patchPolicy = try readSourceFile("20260524000200_storage_read_seen_messages.sql")

        for policy in [baselinePolicy, patchPolicy] {
            XCTAssertTrue(policy.contains("Ping videos room member read"))
            XCTAssertTrue(policy.contains("m.status in ('uploaded', 'seen')"))
            XCTAssertFalse(policy.contains("m.status = 'uploaded'"))
        }
    }

    func testChatImageAttachmentsUsePrivateMediaBucketWithRoomMemberReadPolicy() throws {
        let migration = try readSourceFile("20260524132828_chat_image_attachments.sql")

        XCTAssertTrue(migration.contains("insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)"))
        XCTAssertTrue(migration.contains("values ('ping-media', 'ping-media', false"))
        XCTAssertTrue(migration.contains("array['image/jpeg', 'image/png', 'image/heic', 'image/heif', 'image/gif', 'image/webp']"))
        XCTAssertTrue(migration.contains("create policy \"Ping media owner upload\""))
        XCTAssertTrue(migration.contains("(storage.foldername(name))[1] = auth.uid()::text"))
        XCTAssertTrue(migration.contains("create policy \"Ping media room member read\""))
        XCTAssertTrue(migration.contains("from public.chat_messages cm"))
        XCTAssertTrue(migration.contains("cm.media_path = storage.objects.name"))
        XCTAssertTrue(migration.contains("rm.user_id = auth.uid()"))
        XCTAssertTrue(migration.contains("drop function if exists public.ping_send_chat(uuid, text, uuid, uuid)"))
        XCTAssertTrue(migration.contains("media_path_text text default null"))
        XCTAssertTrue(migration.contains("chat_messages_body_or_media_check"))
    }

    private func readSourceFile(_ relativePath: String) throws -> String {
        let fileName = URL(fileURLWithPath: relativePath).lastPathComponent
        let fileURL = try XCTUnwrap(Bundle(for: Self.self).resourceURL?.appendingPathComponent(fileName))

        return try String(contentsOf: fileURL, encoding: .utf8)
    }
}
