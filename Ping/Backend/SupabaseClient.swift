import Foundation

enum SupabaseJSON {
    static let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom { decoder in
            let container = try decoder.singleValueContainer()
            let value = try container.decode(String.self)

            let iso8601WithFractionalSeconds = ISO8601DateFormatter()
            iso8601WithFractionalSeconds.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            if let date = iso8601WithFractionalSeconds.date(from: value) {
                return date
            }

            let iso8601 = ISO8601DateFormatter()
            iso8601.formatOptions = [.withInternetDateTime]
            if let date = iso8601.date(from: value) {
                return date
            }

            throw DecodingError.dataCorruptedError(
                in: container,
                debugDescription: "Invalid ISO-8601 date: \(value)"
            )
        }
        return decoder
    }()

    static let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }()
}

struct SupabaseConfiguration: Equatable {
    let url: URL
    let anonKey: String

    static func load() throws -> SupabaseConfiguration {
        let environment = ProcessInfo.processInfo.environment
        if let urlString = environment["PING_SUPABASE_URL"],
           let anonKey = environment["PING_SUPABASE_ANON_KEY"],
           let url = URL(string: urlString),
           !anonKey.isEmpty {
            return SupabaseConfiguration(url: url, anonKey: anonKey)
        }

        guard let plistURL = Bundle.main.url(forResource: "Supabase", withExtension: "plist"),
              let data = try? Data(contentsOf: plistURL),
              let plist = try? PropertyListSerialization.propertyList(from: data, options: [], format: nil) as? [String: Any],
              let urlString = plist["SUPABASE_URL"] as? String,
              let url = URL(string: urlString),
              let anonKey = plist["SUPABASE_ANON_KEY"] as? String,
              !anonKey.isEmpty else {
            throw PingError.supabaseConfigurationMissing
        }

        return SupabaseConfiguration(url: url, anonKey: anonKey)
    }

    var authURL: URL {
        url.appendingPathComponent("auth/v1")
    }

    var restURL: URL {
        url.appendingPathComponent("rest/v1")
    }

    var storageURL: URL {
        url.appendingPathComponent("storage/v1")
    }
}

private struct SupabaseAuthUser: Codable {
    let id: String
}

private struct SupabaseAuthResponse: Decodable {
    let accessToken: String
    let refreshToken: String
    let expiresIn: Int
    let expiresAt: Int?
    let user: SupabaseAuthUser

    enum CodingKeys: String, CodingKey {
        case accessToken = "access_token"
        case refreshToken = "refresh_token"
        case expiresIn = "expires_in"
        case expiresAt = "expires_at"
        case user
    }
}

private struct SupabaseSession: Codable {
    let accessToken: String
    let refreshToken: String
    let expiresAt: Date
    let userId: String

    var needsRefresh: Bool {
        expiresAt <= Date().addingTimeInterval(90)
    }
}

@MainActor
final class SupabaseClient: ObservableObject {
    static let shared = SupabaseClient()

    @Published private(set) var currentUid: String?
    @Published private(set) var isConfigured = false

    private let sessionStorageKey = "ping.supabase.session"
    private var configuration: SupabaseConfiguration?
    private var session: SupabaseSession?
    private let urlSession: URLSession

    init(urlSession: URLSession = .shared) {
        self.urlSession = urlSession
    }

    func configureIfNeeded() throws {
        guard !isConfigured else { return }

        configuration = try SupabaseConfiguration.load()
        session = loadStoredSession()
        currentUid = session?.userId
        isConfigured = true
    }

    func bootstrap() async throws -> String {
        try configureIfNeeded()

        if let session, !session.needsRefresh {
            currentUid = session.userId
            return session.userId
        }

        if let session {
            do {
                let refreshed = try await refreshSession(refreshToken: session.refreshToken)
                save(session: refreshed)
                return refreshed.userId
            } catch {
                clearSession()
            }
        }

        let anonymousSession = try await signInAnonymously()
        save(session: anonymousSession)
        return anonymousSession.userId
    }

    func rpcArray<T: Decodable>(_ function: String, body: [String: Any] = [:]) async throws -> [T] {
        let data = try await rpcData(function, body: body)
        if data.isEmpty {
            return []
        }
        return try SupabaseJSON.decoder.decode([T].self, from: data)
    }

    func rpcValue<T: Decodable>(_ function: String, body: [String: Any] = [:]) async throws -> T {
        let data = try await rpcData(function, body: body)
        return try SupabaseJSON.decoder.decode(T.self, from: data)
    }

    func rpcVoid(_ function: String, body: [String: Any] = [:]) async throws {
        _ = try await rpcData(function, body: body)
    }

    func uploadObject(bucket: String, path: String, localURL: URL, contentType: String) async throws {
        let config = try requireConfiguration()
        let token = try await accessToken()
        let uploadURL = objectURL(base: config.storageURL.appendingPathComponent("object"), bucket: bucket, path: path)
        var request = URLRequest(url: uploadURL)
        request.httpMethod = "POST"
        request.setValue(config.anonKey, forHTTPHeaderField: "apikey")
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue(contentType, forHTTPHeaderField: "Content-Type")
        request.setValue("true", forHTTPHeaderField: "x-upsert")
        request.httpBody = try Data(contentsOf: localURL)

        _ = try await send(request)
    }

    func downloadObject(bucket: String, path: String, to localURL: URL) async throws {
        let config = try requireConfiguration()
        let token = try await accessToken()
        let base = config.storageURL
            .appendingPathComponent("object")
            .appendingPathComponent("authenticated")
        let downloadURL = objectURL(base: base, bucket: bucket, path: path)

        var request = URLRequest(url: downloadURL)
        request.httpMethod = "GET"
        request.setValue(config.anonKey, forHTTPHeaderField: "apikey")
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")

        let data = try await send(request)
        try data.write(to: localURL, options: .atomic)
    }

    private func rpcData(_ function: String, body: [String: Any]) async throws -> Data {
        let config = try requireConfiguration()
        let token = try await accessToken()
        let url = config.restURL
            .appendingPathComponent("rpc")
            .appendingPathComponent(function)

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue(config.anonKey, forHTTPHeaderField: "apikey")
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        return try await send(request)
    }

    private func accessToken() async throws -> String {
        try configureIfNeeded()

        if let session, !session.needsRefresh {
            return session.accessToken
        }

        guard let refreshToken = session?.refreshToken else {
            let anonymousSession = try await signInAnonymously()
            save(session: anonymousSession)
            return anonymousSession.accessToken
        }

        do {
            let refreshed = try await refreshSession(refreshToken: refreshToken)
            save(session: refreshed)
            return refreshed.accessToken
        } catch {
            clearSession()
            let anonymousSession = try await signInAnonymously()
            save(session: anonymousSession)
            return anonymousSession.accessToken
        }
    }

    private func signInAnonymously() async throws -> SupabaseSession {
        let config = try requireConfiguration()
        let url = config.authURL.appendingPathComponent("signup")
        let body: [String: Any] = [
            "data": [:],
            "gotrue_meta_security": [:]
        ]
        return try await authRequest(url: url, body: body)
    }

    private func refreshSession(refreshToken: String) async throws -> SupabaseSession {
        let config = try requireConfiguration()
        var components = URLComponents(url: config.authURL.appendingPathComponent("token"), resolvingAgainstBaseURL: false)
        components?.queryItems = [URLQueryItem(name: "grant_type", value: "refresh_token")]
        guard let url = components?.url else { throw PingError.supabaseUnavailable }

        return try await authRequest(url: url, body: ["refresh_token": refreshToken])
    }

    private func authRequest(url: URL, body: [String: Any]) async throws -> SupabaseSession {
        let config = try requireConfiguration()
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue(config.anonKey, forHTTPHeaderField: "apikey")
        request.setValue("Bearer \(config.anonKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let data = try await send(request)
        let response = try SupabaseJSON.decoder.decode(SupabaseAuthResponse.self, from: data)
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
        guard let httpResponse = response as? HTTPURLResponse else {
            throw PingError.supabaseUnavailable
        }

        guard (200..<300).contains(httpResponse.statusCode) else {
            throw PingError.supabaseRequestFailed(
                statusCode: httpResponse.statusCode,
                message: SupabaseClient.errorMessage(from: data)
            )
        }

        return data
    }

    private func requireConfiguration() throws -> SupabaseConfiguration {
        if let configuration {
            return configuration
        }

        try configureIfNeeded()
        guard let configuration else { throw PingError.supabaseUnavailable }
        return configuration
    }

    private func save(session: SupabaseSession) {
        self.session = session
        currentUid = session.userId
        if let data = try? JSONEncoder().encode(session) {
            UserDefaults.standard.set(data, forKey: sessionStorageKey)
        }
    }

    private func loadStoredSession() -> SupabaseSession? {
        guard let data = UserDefaults.standard.data(forKey: sessionStorageKey) else {
            return nil
        }
        return try? JSONDecoder().decode(SupabaseSession.self, from: data)
    }

    private func clearSession() {
        session = nil
        currentUid = nil
        UserDefaults.standard.removeObject(forKey: sessionStorageKey)
    }

    private func objectURL(base: URL, bucket: String, path: String) -> URL {
        path.split(separator: "/").reduce(base.appendingPathComponent(bucket)) { url, component in
            url.appendingPathComponent(String(component))
        }
    }

    private static func errorMessage(from data: Data) -> String {
        guard !data.isEmpty else { return "응답 본문이 없습니다." }

        if let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            for key in ["message", "error_description", "error", "msg"] {
                if let message = object[key] as? String {
                    return message
                }
            }
        }

        return String(data: data, encoding: .utf8) ?? "응답을 해석할 수 없습니다."
    }
}
