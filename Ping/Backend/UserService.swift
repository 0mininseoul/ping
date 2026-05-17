import Foundation

@MainActor
final class UserService {
    private let client: SupabaseClient

    init(client: SupabaseClient = .shared) {
        self.client = client
    }

    func upsert(uid: String, nickname: String) async throws {
        let normalized = SearchableText.normalize(nickname)
        _ = try await client.rpcArray("ping_upsert_profile", body: [
            "nickname_text": nickname,
            "searchable_nickname_text": normalized
        ]) as [PingUser]
    }

    func get(uid: String) async throws -> PingUser? {
        let users: [PingUser] = try await client.rpcArray("ping_get_profile", body: [
            "target_uid": uid
        ])
        return users.first
    }

    func searchByNicknamePrefix(_ prefix: String, excluding excludeUid: String?) async throws -> [PingUser] {
        let normalized = SearchableText.normalize(prefix)
        guard !normalized.isEmpty else { return [] }

        let users: [PingUser] = try await client.rpcArray("ping_search_profiles", body: [
            "search_prefix": normalized
        ])
        return users.filter { $0.id != excludeUid }
    }

    func updateLastUsedRoom(uid: String, roomId: String) async throws {
        try await client.rpcVoid("ping_update_last_used_room", body: [
            "room_uuid": roomId
        ])
    }
}
