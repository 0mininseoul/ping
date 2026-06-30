import Foundation
import PingKit

/// The desktop identity imported onto this device (P4 populates it via QR).
struct PairedAccount: Codable, Sendable {
    let url: URL
    let anonKey: String
    var session: SupabaseSession
}

/// A deep-link target set when the user taps a notification, consumed by
/// `ContentView` to push the matching screen.
enum PingRoute: Hashable {
    case thread(roomId: String, roomName: String?)
}

/// App-wide state: holds the paired account, persists it, and builds a
/// `PingSupabaseClient` whose refreshed sessions are written back to disk.
@MainActor
final class AppEnvironment: ObservableObject {
    static let shared = AppEnvironment()

    @Published private(set) var paired: PairedAccount?

    /// Set by `AppDelegate` when a notification is tapped; `ContentView` reads
    /// it to navigate, then clears it.
    @Published var pendingRoute: PingRoute?

    private let fileURL: URL

    /// One client per identity, shared across every caller. Building a fresh
    /// client per call would defeat the in-flight refresh coalescing inside
    /// `PingSupabaseClient` and let concurrent refreshes race on the single-use
    /// refresh token (empty inbox / empty thread when the loser fails).
    private var cachedClient: PingSupabaseClient?

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
        cachedClient = nil  // New identity → rebuild the shared client.
        persist()
        WatchBridge.shared.sync(account)
    }

    func updateSession(_ session: SupabaseSession) {
        guard var account = paired else { return }
        account.session = session
        paired = account
        persist()
        WatchBridge.shared.sync(account)
    }

    func disconnect() {
        paired = nil
        cachedClient = nil
        try? FileManager.default.removeItem(at: fileURL)
        WatchBridge.shared.unpair()
    }

    private func persist() {
        guard let account = paired, let data = try? JSONEncoder().encode(account) else { return }
        try? data.write(to: fileURL, options: .atomic)
    }

    /// The shared client for the current identity, persisting any refreshed
    /// session. Cached so all callers share one refresh path; rebuilt only when
    /// the identity changes (`setPaired`/`disconnect`).
    func makeClient() -> PingSupabaseClient? {
        guard let account = paired else {
            cachedClient = nil
            return nil
        }
        if let cachedClient { return cachedClient }
        let configuration = PingConfiguration(url: account.url, anonKey: account.anonKey)
        let client = PingSupabaseClient(configuration: configuration, session: account.session) { newSession in
            Task { @MainActor in AppEnvironment.shared.updateSession(newSession) }
        }
        cachedClient = client
        return client
    }
}
