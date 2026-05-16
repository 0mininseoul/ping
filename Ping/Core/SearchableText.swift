import Foundation

enum SearchableText {
    static func normalize(_ value: String) -> String {
        value
            .lowercased()
            .filter { !$0.isWhitespace }
    }

    static func matchesPrefix(target: String, query: String) -> Bool {
        let normalizedQuery = normalize(query)
        guard !normalizedQuery.isEmpty else { return true }
        return normalize(target).hasPrefix(normalizedQuery)
    }
}
