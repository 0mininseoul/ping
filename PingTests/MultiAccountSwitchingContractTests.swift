import XCTest

final class MultiAccountSwitchingContractTests: XCTestCase {
    func testSupabaseClientExposesMultiAccountState() throws {
        let source = try readSourceFile("Ping/Backend/SupabaseClient.swift")
        XCTAssertTrue(source.contains("@Published private(set) var accounts: [StoredAccount]"))
        XCTAssertTrue(source.contains("@Published private(set) var activeUserId: String?"))
        XCTAssertTrue(source.contains("private let accountStore: AccountStore"))
        XCTAssertTrue(source.contains("accountStore: AccountStore = .makeDefault()"))
    }

    func testSupabaseClientConfigureLoadsAccountsFile() throws {
        let source = try readSourceFile("Ping/Backend/SupabaseClient.swift")
        XCTAssertTrue(source.contains("let file = accountStore.load()"))
        XCTAssertTrue(source.contains("session = file.activeAccount?.session"))
    }

    func testSupabaseClientHasMultiAccountMethods() throws {
        let source = try readSourceFile("Ping/Backend/SupabaseClient.swift")
        XCTAssertTrue(source.contains("func addAccount() async throws -> String"))
        XCTAssertTrue(source.contains("func switchTo(userId: String) throws"))
        XCTAssertTrue(source.contains("func removeAccount(userId: String)"))
        XCTAssertTrue(source.contains("func updateActiveNickname(_ nickname: String)"))
        XCTAssertTrue(source.contains("throw PingError.accountNotFound"))
    }

    func testSaveSessionPersistsThroughAccountStore() throws {
        let source = try readSourceFile("Ping/Backend/SupabaseClient.swift")
        XCTAssertTrue(source.contains("accountStore.save(accountsSnapshot())")
            || source.contains("accountStore.save(updated)"))
        XCTAssertTrue(source.contains("upserting(session: session, activateIfFirst: true)"))
    }

    func testLegacyStoreSymbolsRetainedForDowngradeAndRefresh() throws {
        // 기존 세션 컨트랙트가 의존하는 심볼이 사라지지 않았는지 회귀 방어.
        let source = try readSourceFile("Ping/Backend/SupabaseClient.swift")
        XCTAssertTrue(source.contains("private static let fileName = \"SupabaseSession.json\""))
        XCTAssertTrue(source.contains("withRefreshLock"))
        XCTAssertTrue(source.contains("reloadStoredSessionForRefresh"))
        XCTAssertTrue(source.contains("throw PingError.supabaseSessionExpired"))
    }

    func testLocalNotificationCenterHasChatCatchUpHelper() throws {
        let source = try readSourceFile("Ping/Notifications/LocalNotificationCenter.swift")
        XCTAssertTrue(source.contains("func notifyChatCatchUp(roomId: String, roomName: String, unreadCount: Int, latestPreview: String)"))
        XCTAssertTrue(source.contains("\"type\": \"chat\""))
        XCTAssertTrue(source.contains("chat-catchup-"))
    }

    private func readSourceFile(_ relativePath: String) throws -> String {
        let fileName = URL(fileURLWithPath: relativePath).lastPathComponent
        let fileURL = try XCTUnwrap(Bundle(for: Self.self).resourceURL?.appendingPathComponent(fileName))
        return try String(contentsOf: fileURL, encoding: .utf8)
    }
}
