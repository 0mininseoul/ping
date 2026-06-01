import XCTest

final class PingMobilePushPermissionContractTests: XCTestCase {
    func testAppDelegateDoesNotRequestPushPermissionBeforePairing() throws {
        let source = try readProjectSource("PingMobile/AppDelegate.swift")
        let launch = try extract(
            "func application(",
            through: "return true",
            from: source
        )

        XCTAssertTrue(launch.contains("center.setNotificationCategories"))
        XCTAssertFalse(launch.contains("requestAuthorization"))
        XCTAssertFalse(launch.contains("registerForRemoteNotifications"))
    }

    func testPushRegistrarOwnsPermissionRequestAfterPairing() throws {
        let source = try readProjectSource("PingMobile/PushRegistrar.swift")

        XCTAssertTrue(source.contains("func requestAuthorizationAndRegister() async"))
        XCTAssertTrue(source.contains("private var isRequestingAuthorizationAndRegistration = false"))
        XCTAssertTrue(source.contains("guard !isRequestingAuthorizationAndRegistration else { return }"))
        XCTAssertTrue(source.contains("defer { isRequestingAuthorizationAndRegistration = false }"))
        XCTAssertTrue(source.contains("UNUserNotificationCenter.current().requestAuthorization"))
        XCTAssertTrue(source.contains("UIApplication.shared.registerForRemoteNotifications()"))
    }

    func testPairedContentRequestsPushRegistration() throws {
        let source = try readProjectSource("PingMobile/ContentView.swift")

        XCTAssertTrue(source.contains("await PushRegistrar.shared.requestAuthorizationAndRegister()"))
        XCTAssertTrue(source.contains("Task { await PushRegistrar.shared.requestAuthorizationAndRegister() }"))
    }

    private func readProjectSource(_ relativePath: String) throws -> String {
        let testsDir = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
        let projectRoot = testsDir.deletingLastPathComponent()
        return try String(contentsOf: projectRoot.appendingPathComponent(relativePath), encoding: .utf8)
    }

    private func extract(_ start: String, through end: String, from contents: String) throws -> String {
        let startRange = try XCTUnwrap(contents.range(of: start))
        let tail = contents[startRange.lowerBound...]
        let endRange = try XCTUnwrap(tail.range(of: end))
        return String(tail[..<endRange.upperBound])
    }
}
