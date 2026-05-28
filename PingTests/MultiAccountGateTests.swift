import XCTest
@testable import Ping

final class MultiAccountGateTests: XCTestCase {
    private var suiteName: String!
    private var defaults: UserDefaults!

    override func setUpWithError() throws {
        suiteName = "MultiAccountGateTests.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
    }

    override func tearDownWithError() throws {
        defaults.removePersistentDomain(forName: suiteName)
    }

    func testLockedByDefault() {
        XCTAssertFalse(MultiAccountGate.isUnlocked(defaults: defaults))
    }

    func testOwnerNicknameUnlocks() {
        MultiAccountGate.updateUnlock(forNickname: "영민", defaults: defaults)
        XCTAssertTrue(MultiAccountGate.isUnlocked(defaults: defaults))
    }

    func testOwnerNicknameWithWhitespaceUnlocks() {
        MultiAccountGate.updateUnlock(forNickname: "  영민 ", defaults: defaults)
        XCTAssertTrue(MultiAccountGate.isUnlocked(defaults: defaults))
    }

    func testNonOwnerDoesNotUnlock() {
        MultiAccountGate.updateUnlock(forNickname: "철수", defaults: defaults)
        XCTAssertFalse(MultiAccountGate.isUnlocked(defaults: defaults))
    }

    func testStaysUnlockedAfterSwitchingToNonOwner() {
        MultiAccountGate.updateUnlock(forNickname: "영민", defaults: defaults)
        MultiAccountGate.updateUnlock(forNickname: "철수", defaults: defaults)
        XCTAssertTrue(MultiAccountGate.isUnlocked(defaults: defaults))
    }
}
