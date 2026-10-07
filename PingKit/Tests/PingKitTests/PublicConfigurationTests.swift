import Foundation
import Testing
@testable import PingKit

@Suite(.serialized) struct PublicConfigurationTests {
    @Test(arguments: ["valid", "secret", "other-project", "revoked-jwt"])
    func rotatedKeyPreservesIdentityAndRejectsUnsafeConfig(_ mode: String) async throws {
        RotationURLProtocol.mode = mode
        RotationURLProtocol.requests = []
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [RotationURLProtocol.self]
        let original = SupabaseSession(accessToken: "user-jwt", refreshToken: "user-refresh",
                                       expiresAt: Date().addingTimeInterval(3600), userId: "same-user")
        let client = PingSupabaseClient(configuration: PingConfiguration(
            url: URL(string: "https://qxjtprxvjmaxlbtljcjw.supabase.co")!, anonKey: "old-key"),
            session: original, urlSession: URLSession(configuration: config))
        if mode == "valid" || mode == "revoked-jwt" {
            let rows: [String] = try await client.rpcArray("test", body: ["value": "unchanged"])
            #expect(rows.isEmpty)
            let requests = RotationURLProtocol.requests
            #expect(requests.count == (mode == "revoked-jwt" ? 5 : 3))
            #expect(requests[0].httpBody == requests[2].httpBody)
            #expect(requests.last?.value(forHTTPHeaderField: "Authorization") == (mode == "revoked-jwt" ? "Bearer new-user-jwt" : "Bearer user-jwt"))
            #expect(requests[2].value(forHTTPHeaderField: "apikey") == "sb_publishable_new")
        } else {
            do { let _: [String] = try await client.rpcArray("test"); Issue.record("Unsafe configuration accepted") }
            catch { #expect(RotationURLProtocol.requests.count == 2) }
        }
        #expect(await client.currentSession().userId == original.userId)
        if mode != "revoked-jwt" { #expect(await client.currentSession() == original) }
    }
}

final class RotationURLProtocol: URLProtocol, @unchecked Sendable {
    nonisolated(unsafe) static var mode = "valid"
    nonisolated(unsafe) static var requests: [URLRequest] = []
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func stopLoading() {}
    override func startLoading() {
        Self.requests.append(request)
        let isConfig = request.url?.host == "0minping.vercel.app"
        let isAuth = request.url?.path.hasSuffix("/auth/v1/token") == true
        let rejectedJWT = Self.mode == "revoked-jwt" && !isAuth && !isConfig && request.value(forHTTPHeaderField: "Authorization") == "Bearer user-jwt"
        let status = rejectedJWT ? 401 : (isConfig || isAuth || request.value(forHTTPHeaderField: "apikey") == "sb_publishable_new" ? 200 : 401)
        let url = Self.mode == "other-project" ? "https://other.supabase.co" : "https://qxjtprxvjmaxlbtljcjw.supabase.co"
        let key = Self.mode == "secret" ? "sb_secret_private" : "sb_publishable_new"
        if isAuth { #expect(request.value(forHTTPHeaderField: "Authorization") == nil) }
        let body = isAuth ? #"{"access_token":"new-user-jwt","refresh_token":"new-user-refresh","expires_in":3600,"user":{"id":"same-user"}}"# : rejectedJWT ? #"{"code":"PGRST301","message":"JWT signature invalid"}"# : isConfig ? "{\"url\":\"\(url)\",\"anonKey\":\"\(key)\"}" : "[]"
        client?.urlProtocol(self, didReceive: HTTPURLResponse(url: request.url!, statusCode: status,
                                                            httpVersion: nil, headerFields: nil)!, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data(body.utf8))
        client?.urlProtocolDidFinishLoading(self)
    }
}
