import XCTest
@testable import Ping

@MainActor final class NotificationLedgerTests: XCTestCase {
    private var suiteName: String!
    private var defaults: UserDefaults!

    override func setUpWithError() throws {
        suiteName = "NotificationLedgerTests.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
    }

    override func tearDownWithError() throws {
        defaults.removePersistentDomain(forName: suiteName)
    }

    func testRememberThenContains() {
        let ledger = NotificationLedger(defaults: defaults)
        XCTAssertFalse(ledger.contains(.video, uid: "u1", id: "m1"))
        ledger.remember(.video, uid: "u1", id: "m1")
        XCTAssertTrue(ledger.contains(.video, uid: "u1", id: "m1"))
    }

    func testAccountIsolation() {
        let ledger = NotificationLedger(defaults: defaults)
        ledger.remember(.video, uid: "u1", id: "shared")
        XCTAssertTrue(ledger.contains(.video, uid: "u1", id: "shared"))
        XCTAssertFalse(ledger.contains(.video, uid: "u2", id: "shared"))
    }

    func testKindIsolation() {
        let ledger = NotificationLedger(defaults: defaults)
        ledger.remember(.video, uid: "u1", id: "x")
        XCTAssertFalse(ledger.contains(.chat, uid: "u1", id: "x"))
        XCTAssertFalse(ledger.contains(.invite, uid: "u1", id: "x"))
    }

    func testCapBoundsStoredIds() {
        let ledger = NotificationLedger(defaults: defaults, cap: 5)
        for i in 0..<20 { ledger.remember(.chat, uid: "u1", id: "c\(i)") }
        XCTAssertEqual(ledger.ids(.chat, uid: "u1").count, 5)
        // 최신 항목은 남아있다.
        XCTAssertTrue(ledger.contains(.chat, uid: "u1", id: "c19"))
        // 가장 오래된 항목은 밀려났다.
        XCTAssertFalse(ledger.contains(.chat, uid: "u1", id: "c0"))
        // 보관 윈도우는 정확히 최신 5개(c15…c19)다.
        XCTAssertFalse(ledger.contains(.chat, uid: "u1", id: "c14"))
        XCTAssertTrue(ledger.contains(.chat, uid: "u1", id: "c15"))
    }

    func testPersistsAcrossInstances() {
        NotificationLedger(defaults: defaults).remember(.invite, uid: "u1", id: "i1")
        XCTAssertTrue(NotificationLedger(defaults: defaults).contains(.invite, uid: "u1", id: "i1"))
    }

    func testRememberIsIdempotent() {
        let ledger = NotificationLedger(defaults: defaults)
        ledger.remember(.video, uid: "u1", id: "dup")
        ledger.remember(.video, uid: "u1", id: "dup")
        XCTAssertEqual(ledger.ids(.video, uid: "u1"), ["dup"])
    }
}
