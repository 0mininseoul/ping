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

    func testChatDeleteRemovesAttachedMediaObjectBeforeDeletingRow() throws {
        let migration = try readSourceFile("20260524132828_chat_image_attachments.sql")
        let functionBody = try extract(
            "create or replace function public.ping_delete_chat",
            through: "grant execute on function public.ping_delete_chat",
            from: migration
        )

        XCTAssertTrue(functionBody.contains("media_path"))
        XCTAssertTrue(functionBody.contains("delete from storage.objects"))
        XCTAssertTrue(functionBody.contains("bucket_id = 'ping-media'"))
        XCTAssertTrue(functionBody.contains("name = media_path_value"))
        XCTAssertTrue(functionBody.contains("delete from public.chat_messages where id = chat_uuid"))
    }

    func testSenderVideoDeleteRemovesAllRowsSharingStorageObject() throws {
        let migration = try readSourceFile("20260527000100_delete_shared_video_messages.sql")
        let functionBody = try extract(
            "create or replace function public.ping_delete_message",
            through: "grant execute on function public.ping_delete_message",
            from: migration
        )

        XCTAssertTrue(functionBody.contains("video_path text"))
        XCTAssertTrue(functionBody.contains("select sender_uid, video_url"))
        XCTAssertTrue(functionBody.contains("delete from public.messages"))
        XCTAssertTrue(functionBody.contains("video_url = video_path"))
        XCTAssertTrue(functionBody.contains("delete from storage.objects"))
        XCTAssertTrue(functionBody.contains("bucket_id = 'ping-videos'"))
        XCTAssertTrue(functionBody.contains("name = video_path"))
        XCTAssertFalse(functionBody.contains("delete from public.messages where id = message_uuid"))
    }

    func testVideoDeleteOrHideDecisionRunsOnServerAuthUid() throws {
        let migration = try readSourceFile("20260527000200_delete_or_hide_video_message.sql")
        let functionBody = try extract(
            "create or replace function public.ping_remove_video_message",
            through: "grant execute on function public.ping_remove_video_message",
            from: migration
        )

        XCTAssertTrue(functionBody.contains("returns text"))
        XCTAssertTrue(functionBody.contains("select sender_uid, receiver_uid, video_url"))
        XCTAssertTrue(functionBody.contains("if owner_uid = me then"))
        XCTAssertTrue(functionBody.contains("delete from public.messages"))
        XCTAssertTrue(functionBody.contains("video_url = video_path"))
        XCTAssertTrue(functionBody.contains("return 'deleted'"))
        XCTAssertTrue(functionBody.contains("elsif recipient_uid = me then"))
        XCTAssertTrue(functionBody.contains("hidden_for_receiver = true"))
        XCTAssertTrue(functionBody.contains("return 'hidden'"))
        XCTAssertTrue(functionBody.contains("message_not_accessible"))
    }

    func testVideoRemoveMessageDoesNotDirectDeleteStorageObjectsFromSql() throws {
        let migration = try readSourceFile("20260527000300_delete_video_message_rows_only.sql")
        let functionBody = try extract(
            "create or replace function public.ping_remove_video_message",
            through: "grant execute on function public.ping_remove_video_message",
            from: migration
        )

        XCTAssertTrue(functionBody.contains("delete from public.messages"))
        XCTAssertTrue(functionBody.contains("video_url = video_path"))
        XCTAssertFalse(functionBody.contains("delete from storage.objects"))
        XCTAssertTrue(functionBody.contains("Storage API"))
    }

    private func readSourceFile(_ relativePath: String) throws -> String {
        let fileName = URL(fileURLWithPath: relativePath).lastPathComponent
        let fileURL = try XCTUnwrap(Bundle(for: Self.self).resourceURL?.appendingPathComponent(fileName))

        return try String(contentsOf: fileURL, encoding: .utf8)
    }

    private func extract(_ start: String, through end: String, from contents: String) throws -> String {
        let startRange = try XCTUnwrap(contents.range(of: start))
        let tail = contents[startRange.lowerBound...]
        let endRange = try XCTUnwrap(tail.range(of: end))
        return String(tail[..<endRange.upperBound])
    }
}
