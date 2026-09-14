import Foundation

@MainActor
final class DesktopPresenceService {
    private let client: SupabaseClient
    private let deviceIdKey = "ping.desktopPresence.deviceId"

    init(client: SupabaseClient = .shared) {
        self.client = client
    }

    func update(activeRoomId: String?) async throws {
        var body: [String: Any] = [
            "device_id_text": deviceId,
            "platform_text": "macos"
        ]
        if let activeRoomId {
            body["active_room_uuid"] = activeRoomId
        }

        try await client.rpcVoid("ping_update_desktop_presence", body: body)
    }

    /// 같은 방 멤버들의 상태. desktop_presence의 RLS는 본인 행만 허용해서
    /// 서버가 방 멤버십을 확인해주는 RPC로만 읽을 수 있다.
    func roomPresence(roomIds: [String]) async throws -> [DesktopPresenceRow] {
        guard !roomIds.isEmpty else { return [] }

        return try await client.rpcArray("ping_room_desktop_presence", body: [
            "room_uuids": roomIds
        ])
    }

    func clear() async {
        try? await client.rpcVoid("ping_clear_desktop_presence", body: [
            "device_id_text": deviceId,
            "platform_text": "macos"
        ])
    }

    private var deviceId: String {
        if let existing = UserDefaults.standard.string(forKey: deviceIdKey),
           !existing.isEmpty {
            return existing
        }

        let generated = UUID().uuidString
        UserDefaults.standard.set(generated, forKey: deviceIdKey)
        return generated
    }
}
