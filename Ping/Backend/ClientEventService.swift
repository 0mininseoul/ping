import Foundation

@MainActor
final class ClientEventService {
    static let shared = ClientEventService()
    private let client: SupabaseClient

    init(client: SupabaseClient = .shared) {
        self.client = client
    }

    /// Fire-and-forget event logging. Never throws to caller; failures are logged via NSLog.
    func log(_ event: String, properties: [String: Any] = [:]) {
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
