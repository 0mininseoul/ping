import SwiftUI
import PingKit

/// Why a screen has nothing to show.
///
/// The bug this exists to prevent: a dead session and a genuinely empty inbox
/// used to render identically as the green "연결됐어요" screen, so a phone that
/// had been locked out for weeks looked healthy and offered no way back.
enum ConnectionProblem: Equatable {
    /// The refresh token was rejected outright. Only re-pairing fixes this.
    case sessionExpired
    /// A blip — offline, rate limited, server error. It retries on its own.
    case unreachable(detail: String)

    init?(_ error: Error?) {
        guard let error else { return nil }
        if let kitError = error as? PingKitError, kitError == .sessionExpired {
            self = .sessionExpired
        } else {
            self = .unreachable(detail: Self.detail(for: error))
        }
    }

    var title: String {
        switch self {
        case .sessionExpired: return "연결이 끊겼어요"
        case .unreachable: return "서버에 연결할 수 없어요"
        }
    }

    var message: String {
        switch self {
        case .sessionExpired:
            return "이 iPhone의 연결이 만료됐어요. Mac에서 QR 코드를 다시 스캔하면 바로 복구돼요."
        case let .unreachable(detail):
            return "네트워크 상태를 확인해 주세요. 연결되면 자동으로 다시 불러와요.\n(\(detail))"
        }
    }

    var actionTitle: String {
        switch self {
        case .sessionExpired: return "다시 연결하기"
        case .unreachable: return "다시 시도"
        }
    }

    var iconName: String {
        switch self {
        case .sessionExpired: return "link.badge.plus"
        case .unreachable: return "wifi.exclamationmark"
        }
    }

    private static func detail(for error: Error) -> String {
        if let kitError = error as? PingKitError {
            switch kitError {
            case let .requestFailed(statusCode, _): return "HTTP \(statusCode)"
            case .unavailable: return "응답 없음"
            case .sessionExpired: return "세션 만료"
            }
        }
        if let urlError = error as? URLError {
            return "네트워크 \(urlError.code.rawValue)"
        }
        return "알 수 없는 오류"
    }
}

/// Full-screen state for a list that has nothing to fall back on.
struct ConnectionProblemView: View {
    let problem: ConnectionProblem
    let onRetry: () -> Void
    let onReconnect: () -> Void

    var body: some View {
        VStack(spacing: 20) {
            Spacer(minLength: 8)

            Image(systemName: problem.iconName)
                .font(.system(size: 48))
                .foregroundStyle(.orange)

            VStack(spacing: 8) {
                Text(problem.title)
                    .font(.title3.bold())
                Text(problem.message)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.horizontal, 32)

            Button(problem.actionTitle) {
                switch problem {
                case .sessionExpired: onReconnect()
                case .unreachable: onRetry()
                }
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)

            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(uiColor: .systemGroupedBackground))
    }
}

/// Compact bar for a screen that still has usable content behind it — a stale
/// room list or thread stays visible instead of being wiped by a transient error.
struct ConnectionProblemBanner: View {
    let problem: ConnectionProblem
    let onRetry: () -> Void
    let onReconnect: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: problem.iconName)
                .font(.footnote)
            Text(problem.title)
                .font(.footnote.weight(.semibold))
            Spacer(minLength: 8)
            Button(problem.actionTitle) {
                switch problem {
                case .sessionExpired: onReconnect()
                case .unreachable: onRetry()
                }
            }
            .font(.footnote.weight(.semibold))
            .buttonStyle(.plain)
            .foregroundStyle(Color.accentColor)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(Color.orange.opacity(0.14))
        .foregroundStyle(.primary)
    }
}
