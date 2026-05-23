import Foundation
import OSLog

private let signposter = OSSignposter(subsystem: "com.youngminpark.ping.Ping", category: "polling")

@MainActor
final class RoomService {
    private let client: SupabaseClient

    init(client: SupabaseClient = .shared) {
        self.client = client
    }

    @discardableResult
    func createRoom(name: String, ownerUid: String, ownerNickname: String) async throws -> Room {
        let roomName = RoomLimits.sanitizedRoomName(name)
        guard RoomLimits.isValidRoomName(roomName) else { throw PingError.invalidRoomName }

        let rooms: [Room] = try await client.rpcArray("ping_create_room", body: [
            "room_name": roomName,
            "searchable_room_name": SearchableText.normalize(roomName),
            "owner_nickname": ownerNickname
        ])

        guard let room = rooms.first else { throw PingError.supabaseUnavailable }
        return room
    }

    func observeMyRooms(uid: String) -> AsyncStream<[Room]> {
        let client = self.client
        return AsyncStream { continuation in
            let task = Task.detached(priority: .utility) {
                while !Task.isCancelled {
                    let intervalState = signposter.beginInterval("rooms-poll-cycle")
                    do {
                        let rooms: [Room] = try await client.rpcArray("ping_my_rooms")
                        continuation.yield(rooms.sorted { $0.name < $1.name })
                    } catch {
                        continuation.yield([])
                    }
                    signposter.endInterval("rooms-poll-cycle", intervalState)
                    try? await Task.sleep(nanoseconds: 2_000_000_000)
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
        let roomName = RoomLimits.sanitizedRoomName(newName)
        guard RoomLimits.isValidRoomName(roomName) else { throw PingError.invalidRoomName }

        try await client.rpcVoid("ping_rename_room", body: [
            "room_uuid": roomId,
            "new_name": roomName,
            "new_searchable_name": SearchableText.normalize(roomName)
        ])
    }
}
