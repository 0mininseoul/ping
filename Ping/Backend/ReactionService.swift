import Foundation

@MainActor
final class ReactionService {
    private let client: SupabaseClient

    init(client: SupabaseClient = .shared) {
        self.client = client
    }

    /// Returns true if the reaction was added, false if it was removed (toggle).
    @discardableResult
    func toggle(target kind: MessageReaction.TargetKind, targetId: String, emoji: String) async throws -> Bool {
        let result: Bool = try await client.rpcValue("ping_react", body: [
            "target_kind": kind.rawValue,
            "target_uuid": targetId,
            "emoji_text": emoji
        ])
        return result
    }

    func reactions(chatIds: [String], videoIds: [String]) async throws -> [MessageReaction] {
        try await client.rpcArray("ping_message_reactions", body: [
            "chat_ids": chatIds,
            "video_ids": videoIds
        ])
    }
}
