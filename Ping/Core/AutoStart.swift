import Foundation
import OSLog
import ServiceManagement

/// `SMAppService.Status`를 프레임워크 의존 없이 표현한 값. 정책 판정을 순수 함수로 유지하려고 분리했다.
enum AutoStartStatus: Equatable {
    case enabled
    case requiresApproval
    case notRegistered
    case notFound
    case unknown

    /// 등록된 것으로 취급할 상태. `requiresApproval`은 등록은 되어 있고 사용자 승인만 빠진 상태다.
    var isRegistered: Bool {
        self == .enabled || self == .requiresApproval
    }
}

enum AutoStartAction: Equatable {
    case none
    case registerAgent
    case unregisterAgent
    /// 구 로그인 항목(`SMAppService.mainApp`)을 해제한 뒤 agent를 등록한다. 순서가 중요하다.
    case migrateFromMainApp
}

/// 자동 시작 등록 상태를 어떻게 맞출지 정하는 순수 함수. 부작용이 없어 전수 테스트가 가능하다.
enum AutoStartPolicy {
    static func action(
        userChoice: Bool?,
        agentStatus: AutoStartStatus,
        mainAppStatus: AutoStartStatus
    ) -> AutoStartAction {
        guard let userChoice else {
            // 한 번도 선택한 적 없음 = 신규 설치이거나 업데이트 후 첫 실행. 기본 ON으로 켠다.
            if mainAppStatus.isRegistered {
                return .migrateFromMainApp
            }
            return agentStatus == .enabled ? .none : .registerAgent
        }

        guard userChoice else {
            // 사용자가 명시적으로 껐다. 어떤 상태에서도 다시 켜지 않는다.
            return agentStatus.isRegistered ? .unregisterAgent : .none
        }

        // 앱을 옮겼거나 번들이 교체되면 notFound/notRegistered로 떨어진다. 자가 치유한다.
        switch agentStatus {
        case .enabled, .requiresApproval, .unknown:
            return .none
        case .notRegistered, .notFound:
            return .registerAgent
        }
    }
}

/// 자동 시작 등록 상태를 관리한다. `SMAppService`를 호출하는 곳은 이 클래스 하나뿐이다.
@MainActor
final class AutoStartController {
    static let shared = AutoStartController()
    static let agentPlistName = "com.youngminpark.ping.Ping.keepalive.plist"

    private let defaults: UserDefaults
    private let logger = Logger(subsystem: "com.youngminpark.ping.Ping", category: "autostart")

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    private var agent: SMAppService {
        SMAppService.agent(plistName: Self.agentPlistName)
    }

    /// nil이면 사용자가 한 번도 선택하지 않았다는 뜻이다.
    /// `bool(forKey:)`는 false와 미설정을 구분하지 못하므로 반드시 `object(forKey:)`로 읽는다.
    var userChoice: Bool? {
        get { defaults.object(forKey: PingPreferenceKeys.autostartUserChoice) as? Bool }
        set {
            if let newValue {
                defaults.set(newValue, forKey: PingPreferenceKeys.autostartUserChoice)
            } else {
                defaults.removeObject(forKey: PingPreferenceKeys.autostartUserChoice)
            }
        }
    }

    var status: AutoStartStatus {
        Self.map(agent.status)
    }

    static func map(_ status: SMAppService.Status) -> AutoStartStatus {
        switch status {
        case .enabled: return .enabled
        case .requiresApproval: return .requiresApproval
        case .notRegistered: return .notRegistered
        case .notFound: return .notFound
        @unknown default: return .unknown
        }
    }

    /// 설정 토글에서 호출한다. 사용자의 명시적 선택을 저장한다.
    func setEnabled(_ enabled: Bool) throws {
        if enabled {
            try agent.register()
        } else if status.isRegistered {
            try agent.unregister()
        }
        userChoice = enabled
    }

    /// 기동 시 1회 호출. 기본 ON 적용과 구 로그인 항목 마이그레이션을 수행한다.
    func applyPolicyAtLaunch() {
        let choice = userChoice
        let action = AutoStartPolicy.action(
            userChoice: choice,
            agentStatus: status,
            mainAppStatus: Self.map(SMAppService.mainApp.status)
        )

        do {
            switch action {
            case .none:
                break
            case .registerAgent:
                try agent.register()
            case .unregisterAgent:
                try agent.unregister()
            case .migrateFromMainApp:
                // 순서가 중요하다. mainApp을 남긴 채 agent를 등록하면 로그인 시 두 번 실행된다.
                try SMAppService.mainApp.unregister()
                try agent.register()
            }

            if choice == nil {
                userChoice = true
            }
        } catch {
            // 실패하면 userChoice를 저장하지 않는다. 다음 기동에서 다시 시도한다.
            logger.error("auto-start \(String(describing: action), privacy: .public) failed: \(error.localizedDescription, privacy: .public)")
        }
    }
}
