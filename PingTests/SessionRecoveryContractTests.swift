import XCTest
@testable import Ping

/// Regression cover for the 2026-08 lockout: a shared handoff session whose
/// refresh token was consumed by another device left the phone showing a green
/// "연결됐어요" screen for 26 days and popped a dead-end alert on the desktop.
/// The server side is fixed by widening `refresh_token_reuse_interval`; these
/// tests pin the client behaviour that made it invisible and unrecoverable.
@MainActor
final class SupabaseRefreshClassificationTests: XCTestCase {
    private var directory: URL!

    override func setUpWithError() throws {
        try super.setUpWithError()
        setenv("PING_SUPABASE_URL", "https://proj.supabase.co", 1)
        setenv("PING_SUPABASE_ANON_KEY", "test-anon-key", 1)

        directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("ping-refresh-tests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        RefreshStubURLProtocol.reset()
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: directory)
        RefreshStubURLProtocol.reset()
        try super.tearDownWithError()
    }

    /// A 503 while refreshing means "try again shortly", not "your account is
    /// gone". Flattening it into `supabaseSessionExpired` is what made
    /// `BackendRetryPolicy` unreachable and put the modal on screen.
    func testTransientRefreshFailureKeepsItsCauseInsteadOfExpiringTheSession() async throws {
        RefreshStubURLProtocol.tokenStatus = 503
        RefreshStubURLProtocol.tokenBody = #"{"message":"service unavailable"}"#
        let client = try makeClient()

        do {
            _ = try await client.bootstrap()
            XCTFail("expected the refresh failure to propagate")
        } catch let error as PingError {
            guard case let .supabaseRequestFailed(statusCode, _) = error else {
                return XCTFail("expected supabaseRequestFailed, got \(error)")
            }
            XCTAssertEqual(statusCode, 503)
            XCTAssertTrue(BackendRetryPolicy.shouldRetryBootstrap(after: error))
        }
    }

    /// An offline launch — exactly what auto-start at login produces — must reach
    /// the retry ladder rather than the "익명 세션을 복구할 수 없습니다" alert.
    func testOfflineRefreshIsRetryableRatherThanFatal() async throws {
        RefreshStubURLProtocol.failWith = URLError(.notConnectedToInternet)
        let client = try makeClient()

        do {
            _ = try await client.bootstrap()
            XCTFail("expected the refresh failure to propagate")
        } catch {
            XCTAssertFalse(error is PingError, "a network drop must not become a PingError session expiry")
            XCTAssertTrue(BackendRetryPolicy.shouldRetryBootstrap(after: error))
        }
    }

    /// The genuinely-permanent case keeps its existing behaviour: report expiry,
    /// never silently sign in as a brand new anonymous user.
    func testRejectedRefreshTokenStillReportsSessionExpiry() async throws {
        RefreshStubURLProtocol.tokenStatus = 400
        RefreshStubURLProtocol.tokenBody = #"{"error_code":"refresh_token_already_used","msg":"Invalid Refresh Token: Already Used"}"#
        let client = try makeClient()

        do {
            _ = try await client.bootstrap()
            XCTFail("expected a session expiry")
        } catch let error as PingError {
            guard case let .supabaseSessionExpired(userId) = error else {
                return XCTFail("expected supabaseSessionExpired, got \(error)")
            }
            XCTAssertEqual(userId, "contract-test-user")
            XCTAssertFalse(BackendRetryPolicy.shouldRetryBootstrap(after: error))
        }
    }

    // MARK: - Helpers

    private func makeClient() throws -> SupabaseClient {
        let expired = SupabaseSession(
            accessToken: "stale",
            refreshToken: "stale-refresh",
            expiresAt: Date().addingTimeInterval(-600),
            userId: "contract-test-user"
        )
        let file = AccountsFile.migrating(from: expired)
        let store = AccountStore(
            directoryURL: directory,
            defaults: UserDefaults(suiteName: "ping.refresh.tests.\(UUID().uuidString)")!
        )
        store.save(file)

        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [RefreshStubURLProtocol.self]
        return SupabaseClient(
            urlSession: URLSession(configuration: configuration),
            accountStore: store
        )
    }
}

/// Scriptable stand-in for Supabase's `/auth/v1/token` endpoint.
final class RefreshStubURLProtocol: URLProtocol, @unchecked Sendable {
    nonisolated(unsafe) static var tokenStatus = 200
    nonisolated(unsafe) static var tokenBody = ""
    nonisolated(unsafe) static var failWith: Error?

    static func reset() {
        tokenStatus = 200
        tokenBody = ""
        failWith = nil
    }

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func stopLoading() {}

    override func startLoading() {
        if let failWith = Self.failWith {
            client?.urlProtocol(self, didFailWithError: failWith)
            return
        }

        let response = HTTPURLResponse(
            url: request.url!, statusCode: Self.tokenStatus, httpVersion: nil,
            headerFields: ["Content-Type": "application/json"]
        )!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data(Self.tokenBody.utf8))
        client?.urlProtocolDidFinishLoading(self)
    }
}

/// Source-level contracts for the parts that are UI or app-lifecycle shaped.
final class SessionRecoveryContractTests: XCTestCase {
    /// A transient failure must reach the retry ladder, so the catch-all that
    /// turned every error into an expiry has to consult the shared classifier.
    func testDesktopRefreshCatchDefersToTheSharedTransientClassifier() throws {
        let source = try readProjectSource("Ping/Backend/SupabaseClient.swift")

        XCTAssertTrue(source.contains("BackendRetryPolicy.isTransient(error)"))
        XCTAssertTrue(source.contains("throw PingError.supabaseSessionExpired(userId: session.userId)"))
    }

    /// Auto-start launches Ping before Wi-Fi is up. Without a reachability watch
    /// the first failure is terminal until the user quits and relaunches.
    func testDesktopResumesBootstrapWhenTheNetworkComesBack() throws {
        let source = try readProjectSource("Ping/AppDelegate.swift")

        XCTAssertTrue(source.contains("import Network"))
        XCTAssertTrue(source.contains("NWPathMonitor"))
        XCTAssertTrue(source.contains("startNetworkRecoveryMonitor"))
        XCTAssertTrue(source.contains("startBootstrapTaskIfNeeded()"))
    }

    /// The empty inbox and a dead session used to render identically.
    func testInboxSeparatesAnEmptyInboxFromAConnectionFailure() throws {
        let source = try readProjectSource("PingMobile/InboxView.swift")

        XCTAssertTrue(source.contains("loadError"))
        XCTAssertTrue(source.contains("ConnectionProblem("))
        XCTAssertTrue(source.contains("ConnectionProblemView"))
        // The success screen is only reachable when nothing failed.
        let emptyBranch = try extract("} else if rooms.isEmpty", through: "emptyState", from: source)
        XCTAssertTrue(emptyBranch.contains("problem == nil"))
    }

    /// A locked-out phone has to offer the way back, not just describe itself.
    func testDisconnectedInboxOffersRePairing() throws {
        let view = try readProjectSource("PingMobile/ConnectionProblemView.swift")
        XCTAssertTrue(view.contains("case sessionExpired"))
        XCTAssertTrue(view.contains("다시 연결하기"))
        XCTAssertTrue(view.contains("연결이 끊겼어요"))

        let inbox = try readProjectSource("PingMobile/InboxView.swift")
        XCTAssertTrue(inbox.contains("AppEnvironment.shared.disconnect()"))
    }

    /// A blip must not wipe a thread the user is reading.
    func testThreadKeepsItsContentAndSurfacesFailuresInABanner() throws {
        let source = try readProjectSource("PingMobile/ThreadView.swift")

        XCTAssertTrue(source.contains("loadError"))
        XCTAssertTrue(source.contains("ConnectionProblemBanner"))
    }

    /// Polling every 2s against a session that cannot recover is what generated
    /// 26 days of failed requests; slow down while disconnected.
    func testInboxPollingBacksOffWhileDisconnected() throws {
        let source = try readProjectSource("PingMobile/InboxView.swift")

        XCTAssertTrue(source.contains("pollInterval"))
        XCTAssertFalse(
            source.contains("try? await Task.sleep(nanoseconds: 2_000_000_000)"),
            "the poll interval must depend on the connection state, not be a fixed 2s"
        )
    }

    // MARK: - Helpers

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
