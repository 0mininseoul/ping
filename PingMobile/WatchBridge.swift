import Foundation
import WatchConnectivity
import PingKit

/// Sends the paired identity to the Apple Watch so it can fetch videos and reply
/// independently.
@MainActor
final class WatchBridge: NSObject {
    static let shared = WatchBridge()

    func activate() {
        guard WCSession.isSupported() else { return }
        WCSession.default.delegate = self
        WCSession.default.activate()
    }

    func sync(_ account: PairedAccount) {
        guard WCSession.isSupported() else { return }
        let payload = PingHandoffPayload(
            url: account.url,
            anonKey: account.anonKey,
            accessToken: account.session.accessToken,
            refreshToken: account.session.refreshToken,
            expiresAt: account.session.expiresAt,
            userId: account.session.userId
        )
        guard let data = try? payload.encoded(),
              let json = String(data: data, encoding: .utf8) else { return }
        try? WCSession.default.updateApplicationContext(["pairedAccount": json])
    }
}

extension WatchBridge: WCSessionDelegate {
    nonisolated func session(
        _ session: WCSession,
        activationDidCompleteWith activationState: WCSessionActivationState,
        error: Error?
    ) {}

    nonisolated func sessionDidBecomeInactive(_ session: WCSession) {}

    nonisolated func sessionDidDeactivate(_ session: WCSession) {
        session.activate()
    }
}
