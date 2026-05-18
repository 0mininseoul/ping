import Foundation

@MainActor
final class InvitationService {
    private let client: SupabaseClient
    private let pollingIntervalNanoseconds: UInt64 = 2_000_000_000

    init(client: SupabaseClient = .shared) {
        self.client = client
    }

    func send(fromUid: String, fromNickname: String, toUid: String, roomId: String, roomName: String) async throws {
        let _: String = try await client.rpcValue("ping_send_invitation", body: [
            "to_uid": toUid,
            "room_uuid": roomId,
            "from_nickname": fromNickname,
            "room_name_text": roomName
        ])
    }

    @discardableResult
    func inviteUser(toUid: String, fromNickname: String, roomName: String) async throws -> Room {
        let rooms: [Room] = try await client.rpcArray("ping_invite_user", body: [
            "target_uid": toUid,
            "inviter_nickname_text": fromNickname,
            "room_name_text": roomName,
            "searchable_room_name": SearchableText.normalize(roomName)
        ])

        guard let room = rooms.first else { throw PingError.supabaseUnavailable }
        return room
    }

    func observeIncoming(uid: String) -> AsyncStream<[Invitation]> {
        AsyncStream { continuation in
            let task = Task { @MainActor in
                while !Task.isCancelled {
                    do {
                        let invitations: [Invitation] = try await client.rpcArray("ping_incoming_invitations")
                        continuation.yield(invitations)
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

    func accept(invitation: Invitation, myUid: String, myNickname: String, roomService: RoomService) async throws {
        guard let inviteId = invitation.id else { return }

        try await client.rpcVoid("ping_accept_invitation", body: [
            "invitation_uuid": inviteId,
            "nickname_text": myNickname
        ])
    }

    func reject(inviteId: String) async throws {
        try await client.rpcVoid("ping_reject_invitation", body: [
            "invitation_uuid": inviteId
        ])
    }

    func createInviteLink(roomId: String) async throws -> InviteLink {
        let links: [InviteLink] = try await client.rpcArray("ping_create_invite_link", body: [
            "room_uuid": roomId
        ])

        guard let link = links.first else { throw PingError.supabaseUnavailable }
        return link
    }

    @discardableResult
    func acceptInviteLink(token: String, nickname: String) async throws -> Room {
        let rooms: [Room] = try await client.rpcArray("ping_accept_invite_link", body: [
            "invite_token": token,
            "nickname_text": nickname
        ])

        guard let room = rooms.first else { throw PingError.roomUnavailable }
        return room
    }
}
