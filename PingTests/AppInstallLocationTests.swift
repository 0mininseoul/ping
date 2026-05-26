import XCTest
@testable import Ping

final class AppInstallLocationTests: XCTestCase {
    func testSparkleUpdatesRunOnlyFromInstalledApplicationsFolders() {
        XCTAssertTrue(AppInstallLocation.canUseSparkleUpdates(bundleURL: URL(fileURLWithPath: "/Applications/Ping.app")))
        XCTAssertTrue(AppInstallLocation.canUseSparkleUpdates(bundleURL: URL(fileURLWithPath: "/Users/min/Applications/Ping.app")))

        XCTAssertFalse(AppInstallLocation.canUseSparkleUpdates(bundleURL: URL(fileURLWithPath: "/Users/min/Downloads/Ping.app")))
        XCTAssertFalse(AppInstallLocation.canUseSparkleUpdates(bundleURL: URL(fileURLWithPath: "/Volumes/Ping/Ping.app")))
        XCTAssertFalse(AppInstallLocation.canUseSparkleUpdates(bundleURL: URL(fileURLWithPath: "/private/var/folders/ab/cd/AppTranslocation/123/Ping.app")))
    }
}
