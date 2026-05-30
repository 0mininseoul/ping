import Foundation
import WatchConnectivity
import PingKit

struct WatchPairedAccount: Codable, Sendable {
    let url: URL
    let anonKey: String
    var session: SupabaseSession
}

/// Receives the paired identity from the iPhone over WatchConnectivity, persists
/// it, and builds a PingKit client. Also routes tap-to-play message ids.
@MainActor
final class WatchSessionStore: NSObject, ObservableObject {
    static let shared = WatchSessionStore()

    @Published private(set) var paired: WatchPairedAccount?
    @Published var pendingMessageId: String?

    private let fileURL: URL

    override init() {
        let directory = (try? FileManager.default.url(
            for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true
        )) ?? FileManager.default.temporaryDirectory
        fileURL = directory.appendingPathComponent("PingWatchAccount.json")
        super.init()
        load()
    }

    func activate() {
        guard WCSession.isSupported() else { return }
        let session = WCSession.default
        session.delegate = self
        session.activate()
        ingest(applicationContext: session.receivedApplicationContext)
    }

    func setPendingMessage(_ id: String) {
        pendingMessageId = id
    }

    func updateSession(_ session: SupabaseSession) {
        guard var account = paired else { return }
        account.session = session
        paired = account
        persist()
    }

    func makeClient() -> PingSupabaseClient? {
        guard let account = paired else { return nil }
        return PingSupabaseClient(
            configuration: PingConfiguration(url: account.url, anonKey: account.anonKey),
            session: account.session
        ) { newSession in
            Task { @MainActor in WatchSessionStore.shared.updateSession(newSession) }
        }
    }

    fileprivate func ingest(applicationContext: [String: Any]) {
        if applicationContext["unpair"] as? Bool == true {
            paired = nil
            try? FileManager.default.removeItem(at: fileURL)
            return
        }
        guard let json = applicationContext["pairedAccount"] as? String,
              let data = json.data(using: .utf8),
              let payload = try? PingHandoffPayload.decode(data) else { return }
        paired = WatchPairedAccount(url: payload.url, anonKey: payload.anonKey, session: payload.session)
        persist()
    }

    private func load() {
        guard let data = try? Data(contentsOf: fileURL),
              let account = try? JSONDecoder().decode(WatchPairedAccount.self, from: data) else { return }
        paired = account
    }

    private func persist() {
        guard let account = paired, let data = try? JSONEncoder().encode(account) else { return }
        try? data.write(to: fileURL, options: .atomic)
    }
}

extension WatchSessionStore: WCSessionDelegate {
    nonisolated func session(
        _ session: WCSession,
        activationDidCompleteWith activationState: WCSessionActivationState,
        error: Error?
    ) {}

    nonisolated func session(_ session: WCSession, didReceiveApplicationContext applicationContext: [String: Any]) {
        guard let json = applicationContext["pairedAccount"] as? String else { return }
        Task { @MainActor in
            WatchSessionStore.shared.ingest(applicationContext: ["pairedAccount": json])
        }
    }
}
