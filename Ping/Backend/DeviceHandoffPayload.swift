import Foundation

/// Session handoff payload encoded into the pairing QR for iPhone/Apple Watch (P4).
/// Field names must match `PingKit.PingHandoffPayload` so the phone decodes it.
struct DeviceHandoffPayload: Codable {
    let url: URL
    let anonKey: String
    let accessToken: String
    let refreshToken: String
    let expiresAt: Date
    let userId: String
}
