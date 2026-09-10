import UserNotifications

/// 온보딩을 건너뛴 기존 유저를 위한 알림 권한 복구 판단.
///
/// `requestAuthorization`을 온보딩에서만 부르면, 계정이 이미 있는 채로 새로 설치했거나
/// 세션을 핸드오프받은 맥은 권한이 영원히 `.notDetermined`로 남는다. macOS는 이 상태의
/// 앱을 알림 레지스트리에 등록조차 하지 않으므로 시스템 설정 › 알림 목록에서 앱이 통째로
/// 사라진다 — 알림도 안 오고 켤 방법도 없는 유일한 상태다. 거부(`denied`)는 행이 남아
/// 있어 사용자가 되돌릴 수 있으므로 여기서 다시 묻지 않는다.
enum NotificationPermissionRecovery {
    enum Action: Equatable {
        case satisfied
        case request
        case openSettings
    }

    static func shouldRequestAuthorization(for status: UNAuthorizationStatus) -> Bool {
        status == .notDetermined
    }

    static func action(for status: UNAuthorizationStatus) -> Action {
        switch status {
        case .authorized, .provisional, .ephemeral:
            return .satisfied
        case .notDetermined:
            return .request
        case .denied:
            return .openSettings
        @unknown default:
            return .openSettings
        }
    }

    static func statusText(for status: UNAuthorizationStatus) -> String {
        switch status {
        case .authorized, .provisional, .ephemeral:
            return "허용됨"
        case .notDetermined:
            return "아직 요청하지 않음"
        case .denied:
            return "거부됨"
        @unknown default:
            return "확인 필요"
        }
    }
}
