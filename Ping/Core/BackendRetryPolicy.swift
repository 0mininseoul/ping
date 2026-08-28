import Foundation

enum BackendRetryPolicy {
    private static let retryDelays: [TimeInterval] = [3, 5, 10, 20, 30, 60]

    /// Whether an error is worth trying again shortly.
    ///
    /// Transient means the request never got a real answer — we were offline, it
    /// timed out, we were rate limited, or the backend faulted. Permanent means
    /// the backend answered and rejected us (a revoked refresh token, a missing
    /// config); retrying that just burns the rate limit.
    ///
    /// The refresh path in `SupabaseClient` uses the same classifier, so "worth
    /// retrying" and "not a session expiry" cannot drift apart. That split is the
    /// whole fix: before it, a refresh that failed because Wi-Fi was not up yet
    /// became `supabaseSessionExpired`, which this policy then refused to retry,
    /// which put a dead-end alert on screen at every login.
    static func isTransient(_ error: Error) -> Bool {
        if let urlError = error as? URLError {
            return isTransientNetworkError(urlError.code)
        }

        if case let PingError.supabaseRequestFailed(statusCode, _) = error {
            return isTransientStatusCode(statusCode)
        }

        let nsError = error as NSError
        guard nsError.domain == NSURLErrorDomain else { return false }
        return isTransientNetworkError(URLError.Code(rawValue: nsError.code))
    }

    static func shouldRetryBootstrap(after error: Error) -> Bool {
        isTransient(error)
    }

    static func delay(forFailureCount failureCount: Int) -> TimeInterval {
        let index = max(0, min(failureCount - 1, retryDelays.count - 1))
        return retryDelays[index]
    }

    private static func isTransientNetworkError(_ code: URLError.Code) -> Bool {
        switch code {
        case .notConnectedToInternet,
             .networkConnectionLost,
             .timedOut,
             .cannotFindHost,
             .cannotConnectToHost,
             .dnsLookupFailed:
            return true
        default:
            return false
        }
    }

    /// 408 request timeout, 429 rate limit, and every 5xx are the server telling
    /// us to come back — not that this device's identity is gone.
    private static func isTransientStatusCode(_ statusCode: Int) -> Bool {
        statusCode == 408 || statusCode == 429 || (500...599).contains(statusCode)
    }
}
