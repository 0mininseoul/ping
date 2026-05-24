import XCTest
@testable import Ping

final class UpdateReminderStoreTests: XCTestCase {
    func testNotifiesOnlyOncePerLatestVersion() {
        let suiteName = "PingTests.UpdateReminder.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let store = UpdateReminderStore(defaults: defaults)

        XCTAssertTrue(store.shouldNotify(version: "0.3.28"))
        store.markNotified(version: "0.3.28")
        XCTAssertFalse(store.shouldNotify(version: "0.3.28"))
        XCTAssertFalse(store.shouldNotify(version: "0.3.27"))
        XCTAssertTrue(store.shouldNotify(version: "0.3.29"))

        store.markNotified(version: "0.3.29")
        XCTAssertFalse(store.shouldNotify(version: "0.3.29"))
        XCTAssertFalse(store.shouldNotify(version: "0.3.28"))
    }
}
