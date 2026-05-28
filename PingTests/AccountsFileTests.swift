import XCTest
@testable import Ping

final class AccountsFileTests: XCTestCase {
    private func session(_ uid: String, token: String = "t") -> SupabaseSession {
        SupabaseSession(
            accessToken: "\(token)-access-\(uid)",
            refreshToken: "\(token)-refresh-\(uid)",
            expiresAt: Date(timeIntervalSince1970: 10_000),
            userId: uid
        )
    }

    private func account(_ uid: String, nickname: String = "") -> StoredAccount {
        StoredAccount(session: session(uid), nickname: nickname, addedAt: Date(timeIntervalSince1970: 1))
    }

    func testMigratingFromNilIsEmpty() {
        XCTAssertEqual(AccountsFile.migrating(from: nil), .empty)
    }

    func testMigratingFromSessionCreatesSingleActiveAccount() {
        let file = AccountsFile.migrating(from: session("u1"))
        XCTAssertEqual(file.accounts.map(\.userId), ["u1"])
        XCTAssertEqual(file.activeUserId, "u1")
        XCTAssertEqual(file.activeAccount?.nickname, "")
    }

    func testAddingActivatesNewAccountAndIsIdempotentOnUserId() {
        var file = AccountsFile.empty
        file = file.adding(account("a"), activate: true)
        file = file.adding(account("b"), activate: true)
        XCTAssertEqual(file.accounts.map(\.userId), ["a", "b"])
        XCTAssertEqual(file.activeUserId, "b")

        // Re-adding same userId replaces, does not duplicate.
        file = file.adding(account("a", nickname: "renamed"), activate: false)
        XCTAssertEqual(file.accounts.map(\.userId), ["b", "a"])
        XCTAssertEqual(file.activeUserId, "b")
        XCTAssertEqual(file.accounts.first(where: { $0.userId == "a" })?.nickname, "renamed")
    }

    func testRemovingActiveAccountSelectsFirstRemainingAsActive() {
        var file = AccountsFile(accounts: [account("a"), account("b")], activeUserId: "a")
        file = file.removing(userId: "a")
        XCTAssertEqual(file.accounts.map(\.userId), ["b"])
        XCTAssertEqual(file.activeUserId, "b")
    }

    func testRemovingLastAccountClearsActive() {
        var file = AccountsFile(accounts: [account("a")], activeUserId: "a")
        file = file.removing(userId: "a")
        XCTAssertTrue(file.accounts.isEmpty)
        XCTAssertNil(file.activeUserId)
    }

    func testRemovingInactiveAccountKeepsActive() {
        var file = AccountsFile(accounts: [account("a"), account("b")], activeUserId: "a")
        file = file.removing(userId: "b")
        XCTAssertEqual(file.activeUserId, "a")
    }

    func testSwitchingToKnownAccountUpdatesActive() {
        let file = AccountsFile(accounts: [account("a"), account("b")], activeUserId: "a")
        let switched = file.switching(to: "b")
        XCTAssertEqual(switched?.activeUserId, "b")
    }

    func testSwitchingToUnknownAccountReturnsNil() {
        let file = AccountsFile(accounts: [account("a")], activeUserId: "a")
        XCTAssertNil(file.switching(to: "ghost"))
    }

    func testUpdatingNicknameOnlyChangesTarget() {
        let file = AccountsFile(accounts: [account("a", nickname: "x"), account("b", nickname: "y")], activeUserId: "a")
        let updated = file.updatingNickname("영민", for: "a")
        XCTAssertEqual(updated.accounts.first(where: { $0.userId == "a" })?.nickname, "영민")
        XCTAssertEqual(updated.accounts.first(where: { $0.userId == "b" })?.nickname, "y")
    }

    func testUpsertingExistingSessionRefreshesTokensInPlace() {
        var file = AccountsFile(accounts: [account("a")], activeUserId: "a")
        let refreshed = SupabaseSession(
            accessToken: "new-access",
            refreshToken: "new-refresh",
            expiresAt: Date(timeIntervalSince1970: 99_999),
            userId: "a"
        )
        file = file.upserting(session: refreshed, activateIfFirst: true)
        XCTAssertEqual(file.accounts.count, 1)
        XCTAssertEqual(file.accounts[0].accessToken, "new-access")
        XCTAssertEqual(file.accounts[0].expiresAt, Date(timeIntervalSince1970: 99_999))
        XCTAssertEqual(file.activeUserId, "a")
    }

    func testUpsertingNewSessionAppendsAndActivatesWhenNoneActive() {
        let file = AccountsFile.empty.upserting(session: session("first"), activateIfFirst: true)
        XCTAssertEqual(file.accounts.map(\.userId), ["first"])
        XCTAssertEqual(file.activeUserId, "first")
    }

    func testUpsertingNewSessionDoesNotActivateWhenActivateIfFirstFalse() {
        let file = AccountsFile(accounts: [account("a")], activeUserId: "a")
        let updated = file.upserting(session: session("b"), activateIfFirst: false)
        XCTAssertEqual(updated.accounts.map(\.userId), ["a", "b"])
        XCTAssertEqual(updated.activeUserId, "a")
    }

    func testUpdatingNicknameForUnknownUserIsNoOp() {
        let file = AccountsFile(accounts: [account("a", nickname: "x")], activeUserId: "a")
        let updated = file.updatingNickname("ghost-name", for: "missing")
        XCTAssertEqual(updated, file)
    }
}
