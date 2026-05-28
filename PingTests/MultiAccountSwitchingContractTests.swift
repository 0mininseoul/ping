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

    func testAppDelegateUsesPerAccountLedgerAndReload() throws {
        let source = try readSourceFile("Ping/AppDelegate.swift")
        XCTAssertTrue(source.contains("private let ledger = NotificationLedger()"))
        XCTAssertTrue(source.contains("ledger.contains(.video, uid: uid"))
        XCTAssertTrue(source.contains("ledger.remember(.video, uid: uid"))
        XCTAssertTrue(source.contains("ledger.contains(.invite, uid: uid"))
        XCTAssertTrue(source.contains("func reloadForActiveAccount()"))
        XCTAssertTrue(source.contains("func teardownForAccountChange()"))
        XCTAssertTrue(source.contains("await chatRealtime.unsubscribeAll()"))
    }

    func testAppDelegateTriggersChatCatchUp() throws {
        let source = try readSourceFile("Ping/AppDelegate.swift")
        XCTAssertTrue(source.contains("func catchUpChatNotifications(uid: String)"))
        XCTAssertTrue(source.contains("chatMessageService.unreadChatCounts()"))
        XCTAssertTrue(source.contains("notifyChatCatchUp("))
        XCTAssertTrue(source.contains("ledger.contains(.chat, uid: uid"))
    }

    func testAppDelegateHandlesAccountIntents() throws {
        let source = try readSourceFile("Ping/AppDelegate.swift")
        XCTAssertTrue(source.contains("Notification.Name.pingSwitchAccount"))
        XCTAssertTrue(source.contains("Notification.Name.pingAddAccount"))
        XCTAssertTrue(source.contains("Notification.Name.pingRemoveAccount"))
        XCTAssertTrue(source.contains("try SupabaseClient.shared.switchTo(userId:"))
        XCTAssertTrue(source.contains("SupabaseClient.shared.addAccount()"))
        XCTAssertTrue(source.contains("SupabaseClient.shared.removeAccount(userId:"))
    }

    func testAppDelegateUpdatesNicknameAndGateOnBootstrap() throws {
        let source = try readSourceFile("Ping/AppDelegate.swift")
        XCTAssertTrue(source.contains("SupabaseClient.shared.updateActiveNickname("))
        XCTAssertTrue(source.contains("MultiAccountGate.updateUnlock(forNickname:"))
    }

    func testAppDelegateBlocksSwitchWhileSending() throws {
        let source = try readSourceFile("Ping/AppDelegate.swift")
        XCTAssertTrue(source.contains("private var isSwitchingAccount"))
        XCTAssertTrue(source.contains("mirrorViewModel.state != .idle"))
    }

    func testSettingsAccountSectionIsGatedAndPostsIntents() throws {
        let source = try readSourceFile("Ping/UI/Setup/SettingsScene.swift")
        XCTAssertTrue(source.contains("@ObservedObject private var supabase = SupabaseClient.shared"))
        XCTAssertTrue(source.contains("MultiAccountGate.isUnlocked()"))
        XCTAssertTrue(source.contains("Notification.Name.pingSwitchAccount"))
        XCTAssertTrue(source.contains("Notification.Name.pingAddAccount"))
        XCTAssertTrue(source.contains("Notification.Name.pingRemoveAccount"))
        // 영구 손실 경고가 존재해야 한다.
        XCTAssertTrue(source.contains("복구할 수 없습니다"))
    }

    private func readSourceFile(_ relativePath: String) throws -> String {
        let fileName = URL(fileURLWithPath: relativePath).lastPathComponent
        let fileURL = try XCTUnwrap(Bundle(for: Self.self).resourceURL?.appendingPathComponent(fileName))
        return try String(contentsOf: fileURL, encoding: .utf8)
    }
}
