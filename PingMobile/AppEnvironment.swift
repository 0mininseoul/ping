import Foundation
import PingKit

/// The desktop identity imported onto this device (P4 populates it via QR).
struct PairedAccount: Codable, Sendable {
    let url: URL
    let anonKey: String
    var session: SupabaseSession
}

/// App-wide state: holds the paired account, persists it, and builds a
/// `PingSupabaseClient` whose refreshed sessions are written back to disk.
@MainActor
final class AppEnvironment: ObservableObject {
    static let shared = AppEnvironment()

    @Published private(set) var paired: PairedAccount?

    private let fileURL: URL

    init() {
        let directory = (try? FileManager.default.url(
            for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true
        )) ?? FileManager.default.temporaryDirectory
        fileURL = directory.appendingPathComponent("PingPairedAccount.json")
        load()
    }

    func load() {
        guard let data = try? Data(contentsOf: fileURL),
              let account = try? JSONDecoder().decode(PairedAccount.self, from: data) else { return }
        paired = account
    }

    func setPaired(_ account: PairedAccount) {
        paired = account
        persist()
        WatchBridge.shared.sync(account)
    }

    func updateSession(_ session: SupabaseSession) {
        guard var account = paired else { return }
        account.session = session
        paired = account
        persist()
    }

    private func persist() {
        guard let account = paired, let data = try? JSONEncoder().encode(account) else { return }
        try? data.write(to: fileURL, options: .atomic)
    }

    /// Build a client for the current identity, persisting any refreshed session.
    func makeClient() -> PingSupabaseClient? {
        guard let account = paired else { return nil }
        let configuration = PingConfiguration(url: account.url, anonKey: account.anonKey)
        return PingSupabaseClient(configuration: configuration, session: account.session) { newSession in
            Task { @MainActor in AppEnvironment.shared.updateSession(newSession) }
        }
    }
}
