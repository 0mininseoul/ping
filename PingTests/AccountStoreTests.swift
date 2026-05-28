import XCTest
@testable import Ping

final class AccountStoreTests: XCTestCase {
    private var tempDir: URL!
    private var suiteName: String!
    private var defaults: UserDefaults!

    override func setUpWithError() throws {
        tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("AccountStoreTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        suiteName = "AccountStoreTests.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: tempDir)
        defaults.removePersistentDomain(forName: suiteName)
    }

    private func makeStore() -> AccountStore {
        AccountStore(directoryURL: tempDir, defaults: defaults)
    }

    private func session(_ uid: String) -> SupabaseSession {
        SupabaseSession(
            accessToken: "access-\(uid)",
            refreshToken: "refresh-\(uid)",
            expiresAt: Date(timeIntervalSince1970: 50_000),
            userId: uid
        )
    }

    func testLoadReturnsEmptyWhenNothingStored() {
        let file = makeStore().load()
        XCTAssertTrue(file.accounts.isEmpty)
        XCTAssertNil(file.activeUserId)
    }

    func testSaveAndLoadRoundTrip() {
        let store = makeStore()
        let a = StoredAccount(session: session("u1"), nickname: "영민", addedAt: Date(timeIntervalSince1970: 100))
        let b = StoredAccount(session: session("u2"), nickname: "second", addedAt: Date(timeIntervalSince1970: 200))
        store.save(AccountsFile(accounts: [a, b], activeUserId: "u2"))

        let loaded = makeStore().load()
        XCTAssertEqual(loaded.accounts.map(\.userId), ["u1", "u2"])
        XCTAssertEqual(loaded.activeUserId, "u2")
        XCTAssertEqual(loaded.activeAccount?.nickname, "second")
    }

    func testMigratesLegacyFileSessionWhenNoAccountsFile() throws {
        let data = try JSONEncoder().encode(session("legacy-uid"))
        try data.write(to: tempDir.appendingPathComponent("SupabaseSession.json"))

        let loaded = makeStore().load()
        XCTAssertEqual(loaded.accounts.map(\.userId), ["legacy-uid"])
        XCTAssertEqual(loaded.activeUserId, "legacy-uid")
        // 마이그레이션은 Accounts.json을 생성해 둔다.
        XCTAssertTrue(FileManager.default.fileExists(atPath: tempDir.appendingPathComponent("Accounts.json").path))
    }

    func testMigratesLegacyDefaultsSessionWhenNoFiles() throws {
        let data = try JSONEncoder().encode(session("defaults-uid"))
        defaults.set(data, forKey: "ping.supabase.session")

        let loaded = makeStore().load()
        XCTAssertEqual(loaded.activeUserId, "defaults-uid")
        XCTAssertEqual(loaded.accounts.map(\.userId), ["defaults-uid"])
    }

    func testAccountsFileTakesPrecedenceOverLegacy() throws {
        // Accounts.json 존재 시 레거시 무시.
        let store = makeStore()
        store.save(AccountsFile(accounts: [StoredAccount(session: session("real"), nickname: "n", addedAt: Date())], activeUserId: "real"))
        let legacyData = try JSONEncoder().encode(session("stale-legacy"))
        try legacyData.write(to: tempDir.appendingPathComponent("SupabaseSession.json"))

        let loaded = makeStore().load()
        XCTAssertEqual(loaded.activeUserId, "real")
    }

    func testSaveWritesLegacyMirrorForActiveAccount() throws {
        let store = makeStore()
        let other = StoredAccount(session: session("other"), nickname: "x", addedAt: Date())
        let active = StoredAccount(session: session("active"), nickname: "영민", addedAt: Date())
        store.save(AccountsFile(accounts: [other, active], activeUserId: "active"))

        let mirrorData = try Data(contentsOf: tempDir.appendingPathComponent("SupabaseSession.json"))
        let mirror = try JSONDecoder().decode(SupabaseSession.self, from: mirrorData)
        XCTAssertEqual(mirror.userId, "active")

        let defaultsData = try XCTUnwrap(defaults.data(forKey: "ping.supabase.session"))
        let defaultsMirror = try JSONDecoder().decode(SupabaseSession.self, from: defaultsData)
        XCTAssertEqual(defaultsMirror.userId, "active")
    }

    func testSaveClearsLegacyMirrorWhenNoActiveAccount() throws {
        let store = makeStore()
        // First persist an active account so a legacy mirror exists.
        store.save(AccountsFile(accounts: [StoredAccount(session: session("a"), nickname: "n", addedAt: Date())], activeUserId: "a"))
        XCTAssertTrue(FileManager.default.fileExists(atPath: tempDir.appendingPathComponent("SupabaseSession.json").path))

        // Saving with no active account must clear the legacy mirror.
        store.save(AccountsFile(accounts: [], activeUserId: nil))
        XCTAssertFalse(FileManager.default.fileExists(atPath: tempDir.appendingPathComponent("SupabaseSession.json").path))
        XCTAssertNil(defaults.data(forKey: "ping.supabase.session"))
    }
}
