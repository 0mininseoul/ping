import Foundation

@MainActor
final class ClientEventService {
    static let shared = ClientEventService()
    private let client: SupabaseClient
    private var throttle = ClientEventThrottle()

    init(client: SupabaseClient = .shared) {
        self.client = client
    }

    /// Fire-and-forget event logging. Never throws to caller; failures are logged via NSLog.
    func log(_ event: String, properties: [String: Any] = [:]) {
        guard throttle.allows(event, now: Date()) else { return }

        Task { @MainActor in
            do {
                let body: [String: Any] = [
                    "event_name_text": event,
                    "properties_jsonb": properties,
                    "app_version_text": Self.appVersion,
                    "os_version_text": Self.osVersion
                ]
                try await client.rpcVoid("ping_log_event", body: body)
            } catch {
                NSLog("ClientEvent log failed (\(event)): \(error)")
            }
        }
    }

    nonisolated static var appVersion: String {
        (Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String) ?? "unknown"
    }

    nonisolated static var osVersion: String {
        let v = ProcessInfo.processInfo.operatingSystemVersion
        return "\(v.majorVersion).\(v.minorVersion).\(v.patchVersion)"
    }
}

/// 진단 이벤트가 폭주하면 Free 플랜 DB가 통째로 잠긴다. 연결 상태 이벤트는 1건이 아니라
/// 추세만 필요하므로 간격을 두고, 어떤 이벤트든 세션당 상한을 둬서 재발을 막는다.
struct ClientEventThrottle {
    static let diagnosticEvents: Set<String> = ["realtime_disconnected", "realtime_reconnected"]
    static let diagnosticInterval: TimeInterval = 15 * 60
    static let sessionCap = 200

    private var lastLoggedAt: [String: Date] = [:]
    private var counts: [String: Int] = [:]

    mutating func allows(_ event: String, now: Date) -> Bool {
        let count = counts[event, default: 0]
        guard count < Self.sessionCap else { return false }

        if Self.diagnosticEvents.contains(event),
           let last = lastLoggedAt[event],
           now.timeIntervalSince(last) < Self.diagnosticInterval {
            return false
        }

        counts[event] = count + 1
        lastLoggedAt[event] = now
        return true
    }
}
