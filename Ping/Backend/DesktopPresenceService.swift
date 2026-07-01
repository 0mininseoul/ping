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
