import Foundation
import PingKit

/// Holds the latest APNs device token and registers it with the backend once a
/// paired identity exists. Re-runs after pairing (P4) so order doesn't matter.
@MainActor
final class PushRegistrar {
    static let shared = PushRegistrar()

    private let tokenKey = "apnsDeviceToken"
    private(set) var token: String?

    func update(token: String) {
        self.token = token
        UserDefaults.standard.set(token, forKey: tokenKey)
        Task { await registerIfPossible() }
    }

    /// Register the stored token for the current user. No-op without a token or
    /// a paired account.
    func registerIfPossible() async {
        guard let token = token ?? UserDefaults.standard.string(forKey: tokenKey) else { return }
        guard let client = AppEnvironment.shared.makeClient() else { return }
        // TestFlight builds use the production APNs environment (see PUSH_BACKEND_SETUP.md).
        try? await client.registerDeviceToken(token, platform: "ios", environment: "production")
    }
}
