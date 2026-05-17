import Foundation

@MainActor
final class CleanupService {
    private let client: SupabaseClient

    init(client: SupabaseClient = .shared) {
        self.client = client
    }

    func run(uid: String) async throws {
        try await client.rpcVoid("ping_cleanup_expired_data")
    }
}
