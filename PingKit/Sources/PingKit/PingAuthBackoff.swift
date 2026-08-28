import Foundation

/// Retry pacing for token refreshes that fail for a *recoverable* reason.
///
/// Without this, a failing refresh is retried on every call. The inbox and
/// thread screens poll every 2s, so a device whose refresh is failing hammers
/// `/auth/v1/token` ~30x/minute indefinitely — which is both a battery drain and
/// enough on its own to exhaust Supabase's default 150-per-5-minute refresh rate
/// limit for the whole IP, taking other devices on the same network down with it.
///
/// Kept as a pure value so the pacing is testable without sleeping.
struct PingAuthBackoff: Sendable {
    /// Short enough that a brief blip barely shows, long enough that a sustained
    /// outage costs one request every few minutes instead of 30 a minute.
    static let defaultLadder: [TimeInterval] = [2, 5, 15, 60, 300]

    private let ladder: [TimeInterval]
    private(set) var failureCount = 0
    private(set) var retryNotBefore: Date?

    init(ladder: [TimeInterval] = defaultLadder) {
        self.ladder = ladder
    }

    func shouldAttempt(now: Date) -> Bool {
        guard let retryNotBefore else { return true }
        return now >= retryNotBefore
    }

    mutating func recordFailure(now: Date) {
        guard !ladder.isEmpty else { return }
        let step = ladder[min(failureCount, ladder.count - 1)]
        failureCount += 1
        retryNotBefore = now.addingTimeInterval(step)
    }

    mutating func recordSuccess() {
        failureCount = 0
        retryNotBefore = nil
    }
}
