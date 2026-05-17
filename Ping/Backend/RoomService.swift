import Foundation

@MainActor
final class RoomService {
    private let client: SupabaseClient
    private let pollingIntervalNanoseconds: UInt64 = 2_000_000_000

    init(client: SupabaseClient = .shared) {
        self.client = client
    }

    @discardableResult
    func createRoom(name: String, ownerUid: String, ownerNickname: String) async throws -> Room {
        let rooms: [Room] = try await client.rpcArray("ping_create_room", body: [
            "room_name": name,
            "searchable_room_name": SearchableText.normalize(name),
            "owner_nickname": ownerNickname
        ])

        guard let room = rooms.first else { throw PingError.supabaseUnavailable }
        return room
    }

    func observeMyRooms(uid: String) -> AsyncStream<[Room]> {
        AsyncStream { continuation in
            let task = Task { @MainActor in
                while !Task.isCancelled {
                    do {
                        let rooms: [Room] = try await client.rpcArray("ping_my_rooms")
                        continuation.yield(rooms.sorted { $0.name < $1.name })
                    } catch {
                        continuation.yield([])
                    }

                    try? await Task.sleep(nanoseconds: pollingIntervalNanoseconds)
                }

                continuation.finish()
            }

            continuation.onTermination = { _ in task.cancel() }
        }
    }

    func searchOpenRooms(prefix: String) async throws -> [Room] {
        let normalized = SearchableText.normalize(prefix)
        guard !normalized.isEmpty else { return [] }

        let rooms: [Room] = try await client.rpcArray("ping_search_open_rooms", body: [
            "search_prefix": normalized
        ])
        return rooms
    }

    func joinRoom(roomId: String, uid: String, nickname: String) async throws {
        try await client.rpcVoid("ping_join_room", body: [
            "room_uuid": roomId,
            "nickname_text": nickname
        ])
    }

    func leaveRoom(roomId: String, uid: String) async throws {
        try await client.rpcVoid("ping_leave_room", body: [
            "room_uuid": roomId
        ])
    }

    func renameRoom(roomId: String, newName: String) async throws {
        try await client.rpcVoid("ping_rename_room", body: [
            "room_uuid": roomId,
            "new_name": newName,
            "new_searchable_name": SearchableText.normalize(newName)
        ])
    }
}
