import Foundation

/// Thin, cross-platform Supabase client for the iOS/watch receive+reply flow.
///
/// Unlike the macOS `SupabaseClient`, this never signs in anonymously — the
/// identity is imported from the desktop via session handoff (P4). It refreshes
/// the access token with the refresh token when needed and reports the new
/// session through `onSessionUpdate` so the host app can persist it.
public actor PingSupabaseClient {
    private let configuration: PingConfiguration
    private var session: SupabaseSession
    private let urlSession: URLSession
    private let onSessionUpdate: (@Sendable (SupabaseSession) -> Void)?

    public init(
        configuration: PingConfiguration,
        session: SupabaseSession,
        urlSession: URLSession = .shared,
        onSessionUpdate: (@Sendable (SupabaseSession) -> Void)? = nil
    ) {
        self.configuration = configuration
        self.session = session
        self.urlSession = urlSession
        self.onSessionUpdate = onSessionUpdate
    }

    public func currentSession() -> SupabaseSession { session }

    // MARK: - RPC

    public func rpcValue<T: Decodable>(_ function: String, body: [String: any Sendable] = [:]) async throws -> T {
        let data = try await rpcData(function, body: body)
        return try PingJSON.decoder.decode(T.self, from: data)
    }

    public func rpcArray<T: Decodable>(_ function: String, body: [String: any Sendable] = [:]) async throws -> [T] {
        let data = try await rpcData(function, body: body)
        if data.isEmpty { return [] }
        return try PingJSON.decoder.decode([T].self, from: data)
    }

    public func rpcVoid(_ function: String, body: [String: any Sendable] = [:]) async throws {
        _ = try await rpcData(function, body: body)
    }

    // MARK: - Storage

    /// Authenticated download of a private Storage object (receiver is allowed
    /// to read its own messages' videos by RLS).
    public func downloadData(bucket: String, path: String) async throws -> Data {
        let token = try await validAccessToken()
        let base = configuration.storageURL
            .appendingPathComponent("object")
            .appendingPathComponent("authenticated")
        let url = objectURL(base: base, bucket: bucket, path: path)

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue(configuration.anonKey, forHTTPHeaderField: "apikey")
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        return try await send(request)
    }

    // MARK: - Internals

    private func rpcData(_ function: String, body: [String: any Sendable]) async throws -> Data {
        let token = try await validAccessToken()
        let url = configuration.restURL
            .appendingPathComponent("rpc")
            .appendingPathComponent(function)

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue(configuration.anonKey, forHTTPHeaderField: "apikey")
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        return try await send(request)
    }

    /// The in-flight refresh shared by all concurrent callers. Supabase issues a
    /// new refresh token on every swap, so two simultaneous refreshes would make
    /// the second fail with `refresh_token_already_used`. Coalescing collapses
    /// them into one network call that consumes the refresh token exactly once.
    private var refreshTask: Task<SupabaseSession, Error>?

    /// Paces retries after a recoverable refresh failure.
    private var backoff = PingAuthBackoff()

    /// Latched once the refresh token is rejected outright. There is no way back
    /// from this on-device — the identity has to be handed off again — so we stop
    /// asking rather than retrying forever.
    private var isSessionExpired = false

    /// The failure the last refresh attempt produced, replayed to callers that
    /// arrive while the backoff window is still open. Callers get the real cause
    /// instead of a silent empty result.
    private var lastRefreshError: Error?

    /// Whether this client has given up on its session. The host app shows a
    /// re-pair affordance instead of an empty screen when this is true.
    public func isAuthExpired() -> Bool { isSessionExpired }

    private func validAccessToken() async throws -> String {
        if !session.needsRefresh { return session.accessToken }
        return try await refreshedSession().accessToken
    }

    private func refreshedSession() async throws -> SupabaseSession {
        // A coalesced refresh may have completed while this caller was suspended.
        if !session.needsRefresh { return session }

        // Join an in-flight refresh instead of starting a competing one.
        if let refreshTask {
            do {
                return try await refreshTask.value
            } catch {
                throw Self.mapped(error)
            }
        }

        if isSessionExpired { throw PingKitError.sessionExpired }

        // Still inside the backoff window: replay the real cause without adding
        // another request to a server that just told us it could not serve one.
        guard backoff.shouldAttempt(now: Date()) else {
            throw lastRefreshError ?? PingKitError.unavailable
        }

        let refreshToken = session.refreshToken
        let task = Task { try await self.refresh(refreshToken: refreshToken) }
        refreshTask = task
        defer { refreshTask = nil }

        do {
            let refreshed = try await task.value
            backoff.recordSuccess()
            lastRefreshError = nil
            // Only the caller that owns the task commits the new session; the
            // followers above receive the same value without re-applying it.
            session = refreshed
            onSessionUpdate?(refreshed)
            return refreshed
        } catch {
            let mapped = Self.mapped(error)
            if (mapped as? PingKitError) == .sessionExpired {
                isSessionExpired = true
            } else {
                backoff.recordFailure(now: Date())
            }
            lastRefreshError = mapped
            throw mapped
        }
    }

    /// A 400/401 from the token endpoint means the refresh token itself was
    /// rejected (revoked, already used, or unknown) — permanent. Everything else
    /// (offline, 429, 5xx) is a blip and must keep its original cause so callers
    /// and logs can tell the two apart.
    private static func mapped(_ error: Error) -> Error {
        guard case let PingKitError.requestFailed(statusCode, _) = error,
              statusCode == 400 || statusCode == 401 else {
            return error
        }
        return PingKitError.sessionExpired
    }

    private func refresh(refreshToken: String) async throws -> SupabaseSession {
        var components = URLComponents(
            url: configuration.authURL.appendingPathComponent("token"),
            resolvingAgainstBaseURL: false
        )
        components?.queryItems = [URLQueryItem(name: "grant_type", value: "refresh_token")]
        guard let url = components?.url else { throw PingKitError.unavailable }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue(configuration.anonKey, forHTTPHeaderField: "apikey")
        request.setValue("Bearer \(configuration.anonKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: ["refresh_token": refreshToken])

        // Propagate the real failure (e.g. `requestFailed` carrying a 400
        // `refresh_token_already_used`) rather than flattening every error into
        // `sessionExpired`, so callers and diagnostics keep the underlying cause.
        let data = try await send(request)
        let response = try PingJSON.decoder.decode(AuthResponse.self, from: data)
        let expiration = response.expiresAt.map { Date(timeIntervalSince1970: TimeInterval($0)) }
            ?? Date().addingTimeInterval(TimeInterval(response.expiresIn))
        return SupabaseSession(
            accessToken: response.accessToken,
            refreshToken: response.refreshToken,
            expiresAt: expiration,
            userId: response.user.id
        )
    }

    private func send(_ request: URLRequest) async throws -> Data {
        let (data, response) = try await urlSession.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw PingKitError.unavailable }
        guard (200..<300).contains(http.statusCode) else {
            throw PingKitError.requestFailed(
                statusCode: http.statusCode,
                message: String(data: data, encoding: .utf8) ?? ""
            )
        }
        return data
    }

    nonisolated func objectURL(base: URL, bucket: String, path: String) -> URL {
        path.split(separator: "/").reduce(base.appendingPathComponent(bucket)) { url, component in
            url.appendingPathComponent(String(component))
        }
    }

    private struct AuthResponse: Decodable {
        let accessToken: String
        let refreshToken: String
        let expiresIn: Int
        let expiresAt: Int?
        let user: User

        struct User: Decodable { let id: String }

        enum CodingKeys: String, CodingKey {
            case accessToken = "access_token"
            case refreshToken = "refresh_token"
            case expiresIn = "expires_in"
            case expiresAt = "expires_at"
            case user
        }
    }
}
