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

    /// Rate limits and server-side faults are the backend having a bad minute,
    /// not this device losing its identity. Retrying is the whole point of the
    /// ladder, and before this they fell through to the blocking setup alert.
    func testBootstrapRetriesRateLimitedAndServerSideFailures() {
        XCTAssertTrue(BackendRetryPolicy.shouldRetryBootstrap(after: PingError.supabaseRequestFailed(statusCode: 408, message: "request timeout")))
        XCTAssertTrue(BackendRetryPolicy.shouldRetryBootstrap(after: PingError.supabaseRequestFailed(statusCode: 429, message: "rate limit exceeded")))
        XCTAssertTrue(BackendRetryPolicy.shouldRetryBootstrap(after: PingError.supabaseRequestFailed(statusCode: 500, message: "internal error")))
        XCTAssertTrue(BackendRetryPolicy.shouldRetryBootstrap(after: PingError.supabaseRequestFailed(statusCode: 503, message: "service unavailable")))
    }

    /// A rejected credential will be rejected again next time; retrying it just
    /// burns the rate limit and delays telling the user.
    func testBootstrapStillRefusesToRetryRejectedCredentials() {
        XCTAssertFalse(BackendRetryPolicy.shouldRetryBootstrap(after: PingError.supabaseRequestFailed(statusCode: 400, message: "refresh_token_already_used")))
        XCTAssertFalse(BackendRetryPolicy.shouldRetryBootstrap(after: PingError.supabaseRequestFailed(statusCode: 403, message: "forbidden")))
        XCTAssertFalse(BackendRetryPolicy.shouldRetryBootstrap(after: PingError.supabaseRequestFailed(statusCode: 404, message: "not found")))
    }

    /// The refresh path uses the same classifier, so "worth retrying" cannot
    /// drift apart from "not a session expiry".
    func testTransientClassificationIsSharedWithTheRefreshPath() {
        XCTAssertTrue(BackendRetryPolicy.isTransient(URLError(.notConnectedToInternet)))
        XCTAssertTrue(BackendRetryPolicy.isTransient(URLError(.dnsLookupFailed)))
        XCTAssertTrue(BackendRetryPolicy.isTransient(PingError.supabaseRequestFailed(statusCode: 429, message: "")))
        XCTAssertTrue(BackendRetryPolicy.isTransient(PingError.supabaseRequestFailed(statusCode: 502, message: "")))
        XCTAssertFalse(BackendRetryPolicy.isTransient(PingError.supabaseRequestFailed(statusCode: 400, message: "refresh_token_already_used")))
        XCTAssertFalse(BackendRetryPolicy.isTransient(PingError.supabaseConfigurationMissing))
    }

    func testBootstrapRetryDelayBacksOffAndCapsAtOneMinute() {
        XCTAssertEqual(BackendRetryPolicy.delay(forFailureCount: 1), 3)
        XCTAssertEqual(BackendRetryPolicy.delay(forFailureCount: 2), 5)
        XCTAssertEqual(BackendRetryPolicy.delay(forFailureCount: 3), 10)
        XCTAssertEqual(BackendRetryPolicy.delay(forFailureCount: 20), 60)
    }
}
