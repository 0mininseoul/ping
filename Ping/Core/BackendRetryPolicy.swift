import Foundation

enum BackendRetryPolicy {
    private static let retryDelays: [TimeInterval] = [3, 5, 10, 20, 30, 60]

    static func shouldRetryBootstrap(after error: Error) -> Bool {
        if let urlError = error as? URLError {
            return isTransientNetworkError(urlError.code)
        }

        let nsError = error as NSError
        guard nsError.domain == NSURLErrorDomain else { return false }
        return isTransientNetworkError(URLError.Code(rawValue: nsError.code))
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
}
