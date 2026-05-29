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
