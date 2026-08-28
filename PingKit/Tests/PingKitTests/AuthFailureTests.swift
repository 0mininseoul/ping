import Foundation
import Testing
@testable import PingKit

/// Pure backoff arithmetic, so the retry pacing can be checked without sleeping.
@Suite struct AuthBackoffTests {
    @Test func firstFailureBlocksRetriesUntilTheLadderElapses() {
        var backoff = PingAuthBackoff(ladder: [2, 5, 15])
        let t0 = Date(timeIntervalSince1970: 1_000)

        #expect(backoff.shouldAttempt(now: t0))
        backoff.recordFailure(now: t0)

        #expect(!backoff.shouldAttempt(now: t0.addingTimeInterval(1.9)))
        #expect(backoff.shouldAttempt(now: t0.addingTimeInterval(2.1)))
    }

    @Test func repeatedFailuresWalkTheLadderAndCapAtItsLastStep() {
        var backoff = PingAuthBackoff(ladder: [2, 5, 15])
        let t0 = Date(timeIntervalSince1970: 1_000)

        backoff.recordFailure(now: t0)
        #expect(backoff.retryNotBefore == t0.addingTimeInterval(2))

        backoff.recordFailure(now: t0)
        #expect(backoff.retryNotBefore == t0.addingTimeInterval(5))

        backoff.recordFailure(now: t0)
        #expect(backoff.retryNotBefore == t0.addingTimeInterval(15))

        // Past the end of the ladder the wait stays at the cap rather than growing.
        backoff.recordFailure(now: t0)
        #expect(backoff.retryNotBefore == t0.addingTimeInterval(15))
    }

    @Test func successResetsTheLadderSoTheNextBlipStartsShortAgain() {
        var backoff = PingAuthBackoff(ladder: [2, 5, 15])
        let t0 = Date(timeIntervalSince1970: 1_000)

        backoff.recordFailure(now: t0)
        backoff.recordFailure(now: t0)
        backoff.recordSuccess()

        #expect(backoff.shouldAttempt(now: t0))
        backoff.recordFailure(now: t0)
        #expect(backoff.retryNotBefore == t0.addingTimeInterval(2))
    }
}

/// Serialized: every test here scripts the same shared `ScriptedAuthURLProtocol`
/// statics, so running them in parallel would cross-count each other's requests.
@Suite(.serialized) struct AuthFailureLatchTests {
    private func makeClient(session: SupabaseSession) -> PingSupabaseClient {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [ScriptedAuthURLProtocol.self]
        return PingSupabaseClient(
            configuration: PingConfiguration(url: URL(string: "https://proj.supabase.co")!, anonKey: "anon"),
            session: session,
            urlSession: URLSession(configuration: configuration)
        )
    }

    private var expiredSession: SupabaseSession {
        SupabaseSession(
            accessToken: "old", refreshToken: "dead-ref",
            expiresAt: Date().addingTimeInterval(-60), userId: "u-1"
        )
    }

    /// The bug this guards: a phone whose refresh token was revoked retried the
    /// token endpoint every 2s for 26 days. A permanent auth failure must latch
    /// so later calls fail without touching the network.
    @Test func revokedRefreshTokenLatchesAndStopsHittingTheNetwork() async {
        ScriptedAuthURLProtocol.reset()
        ScriptedAuthURLProtocol.authStatus = 400
        ScriptedAuthURLProtocol.authBody = #"{"error_code":"refresh_token_already_used","msg":"Invalid Refresh Token: Already Used"}"#

        let client = makeClient(session: expiredSession)

        var errors: [Error] = []
        for _ in 0..<10 {
            do { _ = try await client.myRooms() } catch { errors.append(error) }
        }

        #expect(ScriptedAuthURLProtocol.refreshes == 1)
        #expect(errors.count == 10)
        #expect(errors.allSatisfy { ($0 as? PingKitError) == .sessionExpired })
    }

    /// A transient failure must not latch — but it must not retry on every call
    /// either, or a 2s poll turns into a refresh storm against the rate limit.
    @Test func transientRefreshFailureBacksOffWithoutLatching() async {
        ScriptedAuthURLProtocol.reset()
        ScriptedAuthURLProtocol.authStatus = 503
        ScriptedAuthURLProtocol.authBody = #"{"message":"service unavailable"}"#

        let client = makeClient(session: expiredSession)

        var errors: [Error] = []
        for _ in 0..<10 {
            do { _ = try await client.myRooms() } catch { errors.append(error) }
        }

        #expect(ScriptedAuthURLProtocol.refreshes == 1)
        #expect(errors.count == 10)
        // The real cause is preserved, never flattened into `sessionExpired`.
        #expect(errors.allSatisfy { ($0 as? PingKitError) != .sessionExpired })
        if case let .requestFailed(statusCode, _)? = errors.first as? PingKitError {
            #expect(statusCode == 503)
        } else {
            Issue.record("expected requestFailed(503), got \(String(describing: errors.first))")
        }
    }

    /// A latched client is unusable by design; recovery is re-pairing, which
    /// builds a fresh client. Verify the latch reports itself so the UI can say so.
    @Test func latchedClientReportsExpiredAuthState() async {
        ScriptedAuthURLProtocol.reset()
        ScriptedAuthURLProtocol.authStatus = 401
        ScriptedAuthURLProtocol.authBody = #"{"msg":"invalid claim"}"#

        let client = makeClient(session: expiredSession)
        #expect(await client.isAuthExpired() == false)

        _ = try? await client.myRooms()

        #expect(await client.isAuthExpired() == true)
    }

    /// A healthy session must not pay any backoff cost.
    @Test func validSessionNeverConsultsTheTokenEndpoint() async {
        ScriptedAuthURLProtocol.reset()
        ScriptedAuthURLProtocol.authStatus = 400

        let live = SupabaseSession(
            accessToken: "fresh", refreshToken: "ref",
            expiresAt: Date().addingTimeInterval(3600), userId: "u-1"
        )
        let client = makeClient(session: live)

        _ = try? await client.myRooms()

        #expect(ScriptedAuthURLProtocol.refreshes == 0)
        #expect(ScriptedAuthURLProtocol.rpcs == 1)
    }
}

/// URLProtocol stub whose `/auth/v1/token` response is scripted per test.
final class ScriptedAuthURLProtocol: URLProtocol, @unchecked Sendable {
    nonisolated(unsafe) static var authStatus = 200
    nonisolated(unsafe) static var authBody = ""
    nonisolated(unsafe) static var refreshCount = 0
    nonisolated(unsafe) static var rpcCount = 0
    static let lock = NSLock()

    static func reset() {
        lock.lock()
        refreshCount = 0
        rpcCount = 0
        authStatus = 200
        authBody = ""
        lock.unlock()
    }

    static var refreshes: Int { lock.lock(); defer { lock.unlock() }; return refreshCount }
    static var rpcs: Int { lock.lock(); defer { lock.unlock() }; return rpcCount }

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func stopLoading() {}

    override func startLoading() {
        let url = request.url!
        let status: Int
        let body: Data

        if url.path.hasSuffix("/auth/v1/token") {
            Self.lock.lock()
            Self.refreshCount += 1
            status = Self.authStatus
            body = Data(Self.authBody.utf8)
            Self.lock.unlock()
        } else {
            Self.lock.lock(); Self.rpcCount += 1; Self.lock.unlock()
            status = 200
            body = Data("[]".utf8)
        }

        let response = HTTPURLResponse(
            url: url, statusCode: status, httpVersion: nil,
            headerFields: ["Content-Type": "application/json"]
        )!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: body)
        client?.urlProtocolDidFinishLoading(self)
    }
}
