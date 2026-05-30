import Foundation

/// Anonymous Supabase session, shaped identically to the macOS app's
/// `SupabaseSession` so a session handed off from desktop (P4) decodes here
/// unchanged: keys `accessToken`, `refreshToken`, `expiresAt` (ISO-8601),
/// `userId`.
public struct SupabaseSession: Codable, Sendable, Equatable {
    public let accessToken: String
    public let refreshToken: String
    public let expiresAt: Date
    public let userId: String

    public init(accessToken: String, refreshToken: String, expiresAt: Date, userId: String) {
        self.accessToken = accessToken
        self.refreshToken = refreshToken
        self.expiresAt = expiresAt
        self.userId = userId
    }

    /// Refresh ~90s before expiry, matching the macOS client.
    public var needsRefresh: Bool {
        accessToken.isEmpty || expiresAt <= Date().addingTimeInterval(90)
    }
}
