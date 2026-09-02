import XCTest
@testable import Ping

@MainActor final class AutoPlayPreferenceTests: XCTestCase {
    private var suiteName: String!
    private var defaults: UserDefaults!

    override func setUpWithError() throws {
        suiteName = "AutoPlayPreferenceTests.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
    }

    override func tearDownWithError() throws {
        defaults.removePersistentDomain(forName: suiteName)
    }

    func testDefaultsToOnWhenNeverSet() {
        XCTAssertTrue(PingAutoPlayPreference.isEnabled(in: defaults))
    }

    func testRespectsExplicitOptOut() {
        defaults.set(false, forKey: PingPreferenceKeys.autoPlayReceivedVideo)
        XCTAssertFalse(PingAutoPlayPreference.isEnabled(in: defaults))

        defaults.set(true, forKey: PingPreferenceKeys.autoPlayReceivedVideo)
        XCTAssertTrue(PingAutoPlayPreference.isEnabled(in: defaults))
    }

    func testPlaysMessagesThatArriveAfterLaunch() {
        let launch = Date()
        XCTAssertTrue(
            PingAutoPlayPreference.shouldAutoPlay(
                messageCreatedAt: launch.addingTimeInterval(30),
                appStartedAt: launch,
                in: defaults
            )
        )
    }

    /// 앱을 껐다 켰을 때 밀려 있던 핑은 알림만 보낸다.
    func testSkipsBacklogFromBeforeLaunch() {
        let launch = Date()
        XCTAssertFalse(
            PingAutoPlayPreference.shouldAutoPlay(
                messageCreatedAt: launch.addingTimeInterval(-30),
                appStartedAt: launch,
                in: defaults
            )
        )
    }

    func testSkipsMessagesWithoutATimestamp() {
        XCTAssertFalse(
            PingAutoPlayPreference.shouldAutoPlay(
                messageCreatedAt: nil,
                appStartedAt: Date(),
                in: defaults
            )
        )
    }

    func testOptOutBeatsAFreshMessage() {
        defaults.set(false, forKey: PingPreferenceKeys.autoPlayReceivedVideo)
        let launch = Date()
        XCTAssertFalse(
            PingAutoPlayPreference.shouldAutoPlay(
                messageCreatedAt: launch.addingTimeInterval(30),
                appStartedAt: launch,
                in: defaults
            )
        )
    }
}
