import Foundation
import Testing
@testable import PingKit

@Suite struct SupabaseSessionTests {
    @Test func decodesMacOSShapeAndRoundTrips() throws {
        // Matches what the desktop app hands off: camelCase keys, ISO-8601 expiry.
        let json = """
        {"accessToken":"acc","refreshToken":"ref","expiresAt":"2026-05-29T00:00:00Z","userId":"u-1"}
        """.data(using: .utf8)!

        let session = try PingJSON.decoder.decode(SupabaseSession.self, from: json)
        #expect(session.accessToken == "acc")
        #expect(session.refreshToken == "ref")
        #expect(session.userId == "u-1")

        let reencoded = try PingJSON.encoder.encode(session)
        let again = try PingJSON.decoder.decode(SupabaseSession.self, from: reencoded)
        #expect(again == session)
    }

    @Test func needsRefreshReflectsExpiry() {
        let expired = SupabaseSession(accessToken: "a", refreshToken: "r", expiresAt: Date().addingTimeInterval(-10), userId: "u")
        let fresh = SupabaseSession(accessToken: "a", refreshToken: "r", expiresAt: Date().addingTimeInterval(3600), userId: "u")
        #expect(expired.needsRefresh)
        #expect(!fresh.needsRefresh)
    }
}

@Suite struct PingJSONTests {
    @Test func decodesFractionalAndPlainISODates() throws {
        struct Wrapper: Decodable { let t: Date }
        let frac = try PingJSON.decoder.decode(Wrapper.self, from: #"{"t":"2026-05-29T12:34:56.789Z"}"#.data(using: .utf8)!)
        let plain = try PingJSON.decoder.decode(Wrapper.self, from: #"{"t":"2026-05-29T12:34:56Z"}"#.data(using: .utf8)!)
        #expect(frac.t.timeIntervalSince1970 > 0)
        #expect(plain.t.timeIntervalSince1970 > 0)
    }
}

@Suite struct RoomTitleTests {
    @Test func titleUsesCanonicalServerNameForEveryClient() {
        let room = PingRoom(
            id: "room",
            name: "A, B, C",
            ownerUid: "a",
            memberUids: ["a", "b", "c"],
            memberNicknames: ["a": "A", "b": "B", "c": "C"],
            createdAt: nil
        )

        #expect(room.displayTitle == "A, B, C")
        #expect(room.title(excluding: "a") == "A, B, C")
        #expect(room.title(excluding: "b") == "A, B, C")
    }
}

@Suite struct VideoMessageTests {
    @Test func decodesRPCRowAndDerivesStoragePath() throws {
        let json = """
        {"id":"m-1","room_id":"r-1","sender_uid":"snd","receiver_uid":"rcv","sender_nickname":"박영민",
         "video_id":"vid-9","video_url":"snd/vid-9.mp4","duration_ms":3000,"status":"uploaded",
         "created_at":"2026-05-29T00:00:00Z","capture_mode":"face_only","aspect_ratio":null}
        """.data(using: .utf8)!

        let message = try PingJSON.decoder.decode(VideoMessage.self, from: json)
        #expect(message.id == "m-1")
        #expect(message.senderNickname == "박영민")
        #expect(message.durationMs == 3000)
        #expect(message.aspectRatio == nil)
        #expect(message.storagePath == "snd/vid-9.mp4")
    }

    @Test func ignoresExtraColumns() throws {
        // RPC returns more columns than we model; decoding must not fail.
        let json = """
        {"id":"m-2","room_id":"r","sender_uid":"s","receiver_uid":"x","sender_nickname":"n",
         "video_id":"v","video_url":"s/v.mp4","duration_ms":3000,"status":"seen",
         "created_at":"2026-05-29T00:00:00Z","mirror_position":"{}","expires_at":"2026-05-30T00:00:00Z",
         "allows_local_save":true}
        """.data(using: .utf8)!
        let message = try PingJSON.decoder.decode(VideoMessage.self, from: json)
        #expect(message.status == "seen")
        #expect(message.captureMode == nil)
    }

    @Test func dedupesSenderRowsByRoomAndVideoPathForMobileThreads() {
        let now = Date(timeIntervalSince1970: 0)
        let messages = [
            makeVideo(id: "sent-1", roomId: "room-a", senderUid: "me", receiverUid: "member-1", videoUrl: "me/shared.mp4", createdAt: now),
            makeVideo(id: "sent-2", roomId: "room-a", senderUid: "me", receiverUid: "member-2", videoUrl: "me/shared.mp4", createdAt: now.addingTimeInterval(1)),
            makeVideo(id: "same-file-other-room", roomId: "room-b", senderUid: "me", receiverUid: "member-3", videoUrl: "me/shared.mp4", createdAt: now.addingTimeInterval(2)),
            makeVideo(id: "incoming", roomId: "room-a", senderUid: "other", receiverUid: "me", videoUrl: "other/shared.mp4", createdAt: now.addingTimeInterval(3))
        ]

        let deduped = VideoMessage.dedupedSenderRows(messages, currentUid: "me")

        #expect(deduped.map(\.id) == ["sent-1", "same-file-other-room", "incoming"])
    }

    private func makeVideo(
        id: String,
        roomId: String,
        senderUid: String,
        receiverUid: String,
        videoUrl: String,
        createdAt: Date
    ) -> VideoMessage {
        VideoMessage(
            id: id,
            roomId: roomId,
            senderUid: senderUid,
            receiverUid: receiverUid,
            senderNickname: "n",
            videoId: "v",
            videoUrl: videoUrl,
            durationMs: 3000,
            status: "uploaded",
            createdAt: createdAt,
            captureMode: "face_only",
            aspectRatio: nil
        )
    }
}

@Suite struct ChatMessageTests {
    @Test func decodesImageAttachmentMetadataAndPreview() throws {
        let json = """
        {"id":"c-1","room_id":"r-1","sender_uid":"snd","sender_nickname":"n",
         "body":"","media_path":"snd/chat-images/c-1.jpg","media_mime_type":"image/jpeg",
         "media_width":1600,"media_height":1200,"media_file_name":"photo.jpg",
         "created_at":"2026-05-29T00:00:00Z"}
        """.data(using: .utf8)!

        let message = try PingJSON.decoder.decode(PingChatMessage.self, from: json)
        #expect(message.hasImage)
        #expect(message.preview == "사진")
        #expect(message.mediaWidth == 1600)
        #expect(message.mediaHeight == 1200)
        #expect(message.mediaFileName == "photo.jpg")
        #expect(message.mediaFileExtension == "jpg")
    }

    @Test func decodesReplyTargets() throws {
        let json = """
        {"id":"c-2","room_id":"r-1","sender_uid":"snd","sender_nickname":"n",
         "body":"답장입니다","reply_to_chat_id":"c-1","reply_to_video_id":null,
         "created_at":"2026-05-29T00:00:00Z"}
        """.data(using: .utf8)!

        let message = try PingJSON.decoder.decode(PingChatMessage.self, from: json)
        #expect(message.replyToChatId == "c-1")
        #expect(message.replyToVideoId == nil)
    }
}

@Suite struct MessageReactionTests {
    @Test func decodesReactionAggregates() throws {
        let json = """
        {"target_kind":"chat","target_id":"c-1","emoji":"👍","total_count":2,"my_reacted":true}
        """.data(using: .utf8)!

        let reaction = try PingJSON.decoder.decode(PingMessageReaction.self, from: json)
        #expect(reaction.targetKind == .chat)
        #expect(reaction.targetId == "c-1")
        #expect(reaction.emoji == "👍")
        #expect(reaction.totalCount == 2)
        #expect(reaction.myReacted)
        #expect(reaction.id == "chat:c-1:👍")
    }
}

@Suite struct ConfigurationTests {
    @Test func derivesSubpaths() {
        let config = PingConfiguration(url: URL(string: "https://proj.supabase.co")!, anonKey: "anon")
        #expect(config.authURL.absoluteString == "https://proj.supabase.co/auth/v1")
        #expect(config.restURL.absoluteString == "https://proj.supabase.co/rest/v1")
        #expect(config.storageURL.absoluteString == "https://proj.supabase.co/storage/v1")
    }

    @Test func objectURLSplitsPathIntoSegments() async {
        let config = PingConfiguration(url: URL(string: "https://proj.supabase.co")!, anonKey: "anon")
        let client = PingSupabaseClient(
            configuration: config,
            session: SupabaseSession(accessToken: "a", refreshToken: "r", expiresAt: Date().addingTimeInterval(3600), userId: "u")
        )
        let base = config.storageURL.appendingPathComponent("object").appendingPathComponent("authenticated")
        let url = client.objectURL(base: base, bucket: "ping-videos", path: "snd/vid-9.mp4")
        #expect(url.absoluteString == "https://proj.supabase.co/storage/v1/object/authenticated/ping-videos/snd/vid-9.mp4")
    }
}

@Suite struct PingProductLinksTests {
    @Test func desktopInstallPageIsCanonicalLandingPage() throws {
        #expect(PingProductLinks.desktopInstallPage.absoluteString == "https://0minping.vercel.app")
        #expect(PingProductLinks.desktopInstallPageText == "0minping.vercel.app")
    }
}

/// Records every request a `PingSupabaseClient` makes so a test can assert that
/// concurrent callers refresh the single-use refresh token exactly once.
final class RefreshCountingURLProtocol: URLProtocol, @unchecked Sendable {
    nonisolated(unsafe) static var refreshCount = 0
    nonisolated(unsafe) static var rpcCount = 0
    static let lock = NSLock()

    static func reset() {
        lock.lock(); refreshCount = 0; rpcCount = 0; lock.unlock()
    }

    static var refreshes: Int {
        lock.lock(); defer { lock.unlock() }; return refreshCount
    }

    static var rpcs: Int {
        lock.lock(); defer { lock.unlock() }; return rpcCount
    }

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func stopLoading() {}

    override func startLoading() {
        let url = request.url!
        let body: Data

        if url.path.hasSuffix("/auth/v1/token") {
            Self.lock.lock(); Self.refreshCount += 1; Self.lock.unlock()
            // Widen the in-flight window so an un-coalesced client would expose
            // overlapping refreshes (and fail this test by counting > 1).
            Thread.sleep(forTimeInterval: 0.05)
            let expiresAt = Int(Date().addingTimeInterval(3600).timeIntervalSince1970)
            body = Data("""
            {"access_token":"new-acc","refresh_token":"new-ref","expires_in":3600,\
            "expires_at":\(expiresAt),"user":{"id":"u-1"}}
            """.utf8)
        } else {
            Self.lock.lock(); Self.rpcCount += 1; Self.lock.unlock()
            body = Data("[]".utf8)
        }

        let response = HTTPURLResponse(
            url: url, statusCode: 200, httpVersion: nil,
            headerFields: ["Content-Type": "application/json"]
        )!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: body)
        client?.urlProtocolDidFinishLoading(self)
    }
}

@Suite struct RefreshCoalescingTests {
    /// Many simultaneous reads on an expired session must collapse into a single
    /// token refresh; otherwise the rotated refresh token would be consumed more
    /// than once and the losers would fail with `refresh_token_already_used`.
    @Test func concurrentReadsRefreshTokenExactlyOnce() async {
        RefreshCountingURLProtocol.reset()

        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [RefreshCountingURLProtocol.self]
        let urlSession = URLSession(configuration: configuration)

        let expired = SupabaseSession(
            accessToken: "old", refreshToken: "old-ref",
            expiresAt: Date().addingTimeInterval(-60), userId: "u-1"
        )
        let client = PingSupabaseClient(
            configuration: PingConfiguration(url: URL(string: "https://proj.supabase.co")!, anonKey: "anon"),
            session: expired,
            urlSession: urlSession
        )

        await withTaskGroup(of: Void.self) { group in
            for _ in 0..<12 {
                group.addTask { _ = try? await client.myRooms() }
            }
        }

        #expect(RefreshCountingURLProtocol.refreshes == 1)
        #expect(RefreshCountingURLProtocol.rpcs == 12)
    }
}
