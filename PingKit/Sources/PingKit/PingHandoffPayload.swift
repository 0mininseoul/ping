import Foundation

/// The pairing payload encoded into the desktop's QR code (P4). The iPhone
/// decodes it to adopt the desktop's anonymous identity. Field names must match
/// what the macOS app encodes (`DeviceHandoffPayload`).
public struct PingHandoffPayload: Codable, Sendable {
    public let url: URL
    public let anonKey: String
    public let accessToken: String
    public let refreshToken: String
    public let expiresAt: Date
    public let userId: String

    public init(url: URL, anonKey: String, accessToken: String, refreshToken: String, expiresAt: Date, userId: String) {
        self.url = url
        self.anonKey = anonKey
        self.accessToken = accessToken
        self.refreshToken = refreshToken
        self.expiresAt = expiresAt
        self.userId = userId
    }

    public var configuration: PingConfiguration {
        PingConfiguration(url: url, anonKey: anonKey)
    }

    public var session: SupabaseSession {
        SupabaseSession(accessToken: accessToken, refreshToken: refreshToken, expiresAt: expiresAt, userId: userId)
    }

    /// Decode a handoff payload from scanned QR bytes (ISO-8601 dates).
    public static func decode(_ data: Data) throws -> PingHandoffPayload {
        try PingJSON.decoder.decode(PingHandoffPayload.self, from: data)
    }

    /// Encode for transport (e.g. WatchConnectivity), ISO-8601 dates — symmetric
    /// with `decode(_:)`.
    public func encoded() throws -> Data {
        try PingJSON.encoder.encode(self)
    }
}
