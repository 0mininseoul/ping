import AppKit
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

/// launchd가 띄운 인스턴스와 사용자가 띄운 인스턴스가 겹치는 것을 막는다.
///
/// `SMAppService.register()`는 잡을 즉시 로드하고, plist의 `RunAtLoad`가 true라 launchd는
/// 그 자리에서 `Contents/MacOS/Ping`을 exec한다. 즉 **실행 중인 앱이 자기 자신을 등록하면
/// 두 번째 프로세스가 뜬다.** launchd의 exec는 LaunchServices를 거치지 않아 중복 제거가 안 된다.
/// 그대로 두면 메뉴바 아이콘 2개, realtime 구독 2벌, 알림 2배가 된다.
enum SingleInstanceGuard {
    /// 이 판정은 기동 직후에만 호출된다. 우리 프로세스는 방금 떴으므로 목록의 다른 pid는
    /// 전부 우리보다 먼저 뜬 인스턴스다.
    static func shouldYield(runningPIDs: [pid_t], currentPID: pid_t) -> Bool {
        runningPIDs.contains { $0 != currentPID }
    }

    static func runningPIDs(forBundleIdentifier bundleIdentifier: String) -> [pid_t] {
        NSRunningApplication
            .runningApplications(withBundleIdentifier: bundleIdentifier)
            .map(\.processIdentifier)
    }
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
            return reconcileEnabled(agentStatus)
        }

        guard userChoice else {
            // 사용자가 명시적으로 껐다. 어떤 상태에서도 다시 켜지 않는다.
            return agentStatus.isRegistered ? .unregisterAgent : .none
        }

        return reconcileEnabled(agentStatus)
    }

    /// "켜져 있어야 한다"가 확정된 뒤 현재 상태를 어떻게 맞출지 정한다.
    /// 첫 실행 분기와 자가 치유 분기가 같은 판단을 쓰도록 한 곳에 모았다 —
    /// 어긋나면 한쪽만 실패할 `register()`를 매 기동 반복한다.
    private static func reconcileEnabled(_ agentStatus: AutoStartStatus) -> AutoStartAction {
        switch agentStatus {
        case .enabled, .requiresApproval, .unknown:
            // requiresApproval은 사용자가 시스템 설정에서 껐다는 뜻이라 존중한다.
            // unknown은 우리가 모르는 상태다. 모르면 건드리지 않는다.
            return .none
        case .notRegistered, .notFound:
            // 앱을 옮겼거나 번들이 교체되면 여기로 떨어진다. 자가 치유한다.
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
    ///
    /// 저장이 OS 호출보다 **먼저**다. 나중에 저장하면 `unregister()`가 실패했을 때 "끄겠다"는
    /// 의사가 유실되고, 다음 기동에서 정책이 여전히 켜진 상태로 판단해 영구히 켜진 채 남는다.
    /// 먼저 저장해 두면 OS 호출이 실패해도 다음 기동에서 정책이 양방향으로 자가 치유한다.
    func setEnabled(_ enabled: Bool) throws {
        userChoice = enabled

        if enabled {
            try agent.register()
        } else if status.isRegistered {
            try agent.unregister()
        }
    }

    /// 기동 시 1회 호출. 기본 ON 적용과 구 로그인 항목 마이그레이션을 수행한다.
    func applyPolicyAtLaunch() {
        // DerivedData나 .dmg에서 실행된 빌드는 등록하지 않는다. 등록하면 Xcode의 Stop(SIGKILL)이
        // 비정상 종료로 잡혀 KeepAlive가 개발 빌드를 되살리고, DerivedData를 지우면
        // 시스템 설정에 죽은 로그인 항목이 남는다.
        guard AppInstallLocation.canUseSparkleUpdates() else { return }

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
                // agent 등록이 먼저다. mainApp을 먼저 해제하면 register()가 실패했을 때
                // 둘 다 없는 상태로 남고 복구 경로가 없다. 이 순서면 최악의 경우가
                // "둘 다 등록됨"이고, 그건 중복 가드가 막고 다음 기동이 정리한다.
                //
                // 이미 등록됐으면 다시 부르지 않는다. mainApp 해제가 실패해 다음 기동에서
                // 이 경로를 재시도할 때, 등록된 agent에 register()가 던지면 아래 해제에
                // 영영 도달하지 못해 mainApp이 남은 채로 수렴하지 않는다.
                if !status.isRegistered {
                    try agent.register()
                }
                try SMAppService.mainApp.unregister()
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
