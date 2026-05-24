import Foundation

struct UpdateReminderPolicy {
    static func shouldNotify(version: String, lastNotifiedVersion: String?) -> Bool {
        let candidate = normalized(version)
        guard !candidate.isEmpty else { return false }

        guard let lastNotifiedVersion else { return true }
        let last = normalized(lastNotifiedVersion)
        guard !last.isEmpty else { return true }

        return compare(candidate, to: last) == .orderedDescending
    }

    static func normalized(_ version: String) -> String {
        version.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func compare(_ lhs: String, to rhs: String) -> ComparisonResult {
        let lhsComponents = numericComponents(lhs)
        let rhsComponents = numericComponents(rhs)

        guard !lhsComponents.isEmpty, !rhsComponents.isEmpty else {
            return lhs.compare(rhs, options: [.numeric, .caseInsensitive])
        }

        let count = max(lhsComponents.count, rhsComponents.count)
        for index in 0..<count {
            let left = index < lhsComponents.count ? lhsComponents[index] : 0
            let right = index < rhsComponents.count ? rhsComponents[index] : 0
            if left < right { return .orderedAscending }
            if left > right { return .orderedDescending }
        }
        return .orderedSame
    }

    private static func numericComponents(_ version: String) -> [Int] {
        version
            .split { !$0.isNumber }
            .compactMap { Int($0) }
    }
}

final class UpdateReminderStore {
    private static let key = "Ping.lastNotifiedUpdateVersion"

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    func shouldNotify(version: String) -> Bool {
        UpdateReminderPolicy.shouldNotify(
            version: version,
            lastNotifiedVersion: defaults.string(forKey: Self.key)
        )
    }

    func markNotified(version: String) {
        let normalized = UpdateReminderPolicy.normalized(version)
        guard !normalized.isEmpty else { return }
        defaults.set(normalized, forKey: Self.key)
    }
}
