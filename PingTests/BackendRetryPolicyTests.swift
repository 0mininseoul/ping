import XCTest
@testable import Ping

final class BackendRetryPolicyTests: XCTestCase {
    func testBootstrapRetriesTransientNetworkStartupFailures() {
        XCTAssertTrue(BackendRetryPolicy.shouldRetryBootstrap(after: URLError(.notConnectedToInternet)))
        XCTAssertTrue(BackendRetryPolicy.shouldRetryBootstrap(after: URLError(.networkConnectionLost)))
        XCTAssertTrue(BackendRetryPolicy.shouldRetryBootstrap(after: URLError(.timedOut)))
        XCTAssertTrue(BackendRetryPolicy.shouldRetryBootstrap(after: URLError(.cannotFindHost)))
        XCTAssertTrue(BackendRetryPolicy.shouldRetryBootstrap(after: URLError(.cannotConnectToHost)))
        XCTAssertTrue(BackendRetryPolicy.shouldRetryBootstrap(after: URLError(.dnsLookupFailed)))
    }

    func testBootstrapDoesNotRetryPermanentSetupOrAuthFailures() {
        XCTAssertFalse(BackendRetryPolicy.shouldRetryBootstrap(after: PingError.supabaseConfigurationMissing))
        XCTAssertFalse(BackendRetryPolicy.shouldRetryBootstrap(after: PingError.supabaseSessionExpired(userId: "u1")))
        XCTAssertFalse(BackendRetryPolicy.shouldRetryBootstrap(after: PingError.supabaseRequestFailed(statusCode: 401, message: "JWT expired")))
    }

    func testBootstrapRetryDelayBacksOffAndCapsAtOneMinute() {
        XCTAssertEqual(BackendRetryPolicy.delay(forFailureCount: 1), 3)
        XCTAssertEqual(BackendRetryPolicy.delay(forFailureCount: 2), 5)
        XCTAssertEqual(BackendRetryPolicy.delay(forFailureCount: 3), 10)
        XCTAssertEqual(BackendRetryPolicy.delay(forFailureCount: 20), 60)
    }
}
