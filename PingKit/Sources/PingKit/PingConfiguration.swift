import Foundation

/// Supabase project endpoint + anon key. The anon key is the public client key
/// (safe to ship); per-user authorization comes from the session access token.
public struct PingConfiguration: Sendable, Equatable {
    public let url: URL
    public let anonKey: String

    public init(url: URL, anonKey: String) {
        self.url = url
        self.anonKey = anonKey
    }

    var authURL: URL { url.appendingPathComponent("auth/v1") }
    var restURL: URL { url.appendingPathComponent("rest/v1") }
    var storageURL: URL { url.appendingPathComponent("storage/v1") }
}

public enum PingKitError: Error, Equatable, Sendable {
    case requestFailed(statusCode: Int, message: String)
    case unavailable
    case sessionExpired
}
