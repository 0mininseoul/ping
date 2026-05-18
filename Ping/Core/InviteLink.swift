import Foundation

enum PingInviteLink {
    private static let defaultBaseURL = URL(string: "https://ping0min.vercel.app")!

    static func url(for token: String) -> URL {
        configuredBaseURL()
            .appendingPathComponent("invite")
            .appendingPathComponent(token)
    }

    static func token(from text: String) -> String? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        if let url = URL(string: trimmed), let token = token(from: url) {
            return token
        }

        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-_"))
        guard trimmed.count >= 8,
              trimmed.count <= 64,
              trimmed.rangeOfCharacter(from: allowed.inverted) == nil else {
            return nil
        }

        return trimmed
    }

    static func token(from url: URL) -> String? {
        if url.scheme == "ping" {
            if url.host == "invite" {
                return url.pathComponents.dropFirst().first
            }

            if let token = URLComponents(url: url, resolvingAgainstBaseURL: false)?
                .queryItems?
                .first(where: { $0.name == "token" })?
                .value {
                return token
            }
        }

        let components = url.pathComponents
        if let inviteIndex = components.firstIndex(of: "invite"),
           components.indices.contains(inviteIndex + 1) {
            return components[inviteIndex + 1]
        }

        return URLComponents(url: url, resolvingAgainstBaseURL: false)?
            .queryItems?
            .first(where: { $0.name == "token" })?
            .value
    }

    private static func configuredBaseURL() -> URL {
        let environment = ProcessInfo.processInfo.environment
        if let value = environment["PING_INVITE_BASE_URL"],
           let url = URL(string: value) {
            return url
        }

        if let plistURL = Bundle.main.url(forResource: "Supabase", withExtension: "plist"),
           let data = try? Data(contentsOf: plistURL),
           let plist = try? PropertyListSerialization.propertyList(from: data, options: [], format: nil) as? [String: Any],
           let value = plist["PING_INVITE_BASE_URL"] as? String,
           let url = URL(string: value) {
            return url
        }

        return defaultBaseURL
    }
}
