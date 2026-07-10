import XCTest
@testable import Ping

final class SelfCaptureFilterPolicyTests: XCTestCase {
    private struct Application: Equatable {
        let bundleIdentifier: String?
        let processID: Int32
    }

    func testBundleIdentifierMatchesEveryProcessOwnedByPing() {
        let applications = [
            Application(bundleIdentifier: "com.example.browser", processID: 10),
            Application(bundleIdentifier: "com.youngminpark.ping.Ping", processID: 20),
            Application(bundleIdentifier: "com.youngminpark.ping.Ping", processID: 21)
        ]

        let matches = SelfCaptureFilterPolicy.matchingApplications(
            in: applications,
            bundleIdentifier: "com.youngminpark.ping.Ping",
            processID: 999,
            bundleIdentifierOf: \Application.bundleIdentifier,
            processIDOf: \Application.processID
        )

        XCTAssertEqual(matches, Array(applications[1...2]))
    }

    func testProcessIDIsUsedWhenBundleIdentifierIsUnavailable() {
        let applications = [
            Application(bundleIdentifier: "com.example.browser", processID: 10),
            Application(bundleIdentifier: nil, processID: 20)
        ]

        let matches = SelfCaptureFilterPolicy.matchingApplications(
            in: applications,
            bundleIdentifier: nil,
            processID: 20,
            bundleIdentifierOf: \Application.bundleIdentifier,
            processIDOf: \Application.processID
        )

        XCTAssertEqual(matches, [applications[1]])
    }

    func testMissingCurrentApplicationReturnsNoExclusions() {
        let applications = [
            Application(bundleIdentifier: "com.example.browser", processID: 10)
        ]

        let matches = SelfCaptureFilterPolicy.matchingApplications(
            in: applications,
            bundleIdentifier: "com.youngminpark.ping.Ping",
            processID: 20,
            bundleIdentifierOf: \Application.bundleIdentifier,
            processIDOf: \Application.processID
        )

        XCTAssertTrue(matches.isEmpty)
    }
}
