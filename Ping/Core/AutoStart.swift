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
    case reregisterAgent
    case unregisterAgent
    /// 구 로그인 항목(`SMAppService.mainApp`)을 해제한 뒤 agent를 등록한다. 순서가 중요하다.
    case migrateFromMainApp
}

enum PingLaunchOrigin {
    static let agentServiceName = "com.youngminpark.ping.Ping.keepalive"

    static func isAgentManaged(
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) -> Bool {
        environment["XPC_SERVICE_NAME"] == agentServiceName
    }
}

enum SingleInstanceAction: Equatable {
    case proceed
    case yield
    case replaceExisting([pid_t])
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
    static func action(
        runningPIDs: [pid_t],
        currentPID: pid_t,
        isAgentManaged: Bool
    ) -> SingleInstanceAction {
        let others = runningPIDs.filter { $0 != currentPID }
        guard !others.isEmpty else { return .proceed }
        return isAgentManaged ? .replaceExisting(others) : .yield
    }

    static func runningPIDs(forBundleIdentifier bundleIdentifier: String) -> [pid_t] {
        NSRunningApplication
            .runningApplications(withBundleIdentifier: bundleIdentifier)
            .map(\.processIdentifier)
    }
}

/// 소유권 이전을 끝까지 완수한다.
///
/// 설계상 launchd가 띄운 인스턴스가 이겨야 한다(2026-09-15 keepalive-ownership 스펙).
/// 그래야 살아남은 프로세스를 launchd가 감시하고 비정상 종료 뒤 되살릴 수 있다.
/// 그런데 `NSRunningApplication.terminate()`가 true를 돌려줘도 그건 quit 이벤트를
/// **보냈다**는 뜻일 뿐이다. 기동 직후의 전임자는 아직 이벤트 루프를 못 띄워 그걸 흘리고,
/// 확인도 재시도도 없던 탓에 두 인스턴스가 그대로 남았다 — 창이 두 개 열리던 증상이다.
///
/// 그래서 매 시도마다 다시 요청한다. 한 번만 보내고 기다리면 흘러간 요청은 영영 다시
/// 오지 않아, 남는 결말이 강제 종료뿐이다. 기한을 넘긴 경우에만 강제한다.
enum DuplicateInstanceTerminator {
    /// 강제 종료까지 간 pid를 돌려준다. 주입된 클로저만 갈아끼우면 전수 테스트가 된다.
    @discardableResult
    static func replace(
        pids: [pid_t],
        politeQuit: (pid_t) -> Void,
        hasExited: (pid_t) -> Bool,
        forceQuit: (pid_t) -> Void,
        waitStep: () -> Void,
        maxChecks: Int
    ) -> [pid_t] {
        guard !pids.isEmpty else { return [] }

        var remaining = pids
        var checks = 0

        while true {
            remaining = remaining.filter { !hasExited($0) }
            if remaining.isEmpty { return [] }
            if checks >= maxChecks { break }

            for pid in remaining {
                politeQuit(pid)
            }
            waitStep()
            checks += 1
        }

        for pid in remaining {
            forceQuit(pid)
        }
        return remaining
    }
}

/// 재등록 뒤 소유권을 누가 갖는지 정한다.
///
/// 원래 설계는 launchd가 띄운 신참이 전임자에게 종료를 **요청**하는 것이었는데,
/// 그 요청은 샌드박스에서 전달되지 않는다. `NSRunningApplication.terminate()`는 quit
/// AppleEvent를 보내는 방식이고, Ping은 `com.apple.security.app-sandbox`가 켜진 채
/// `com.apple.security.automation.apple-events` 권한이 없다. 그래서 0.3.75까지 중복
/// 인스턴스가 그대로 남았다(창이 두 개 열리는 증상).
///
/// 남의 프로세스를 끝내는 건 신뢰할 수 없지만 **자기 자신을 끝내는 것은 언제나 허용된다.**
/// 그래서 방향을 뒤집는다: 재등록을 한 쪽이, launchd가 새 인스턴스를 띄운 것을 확인하면
/// 스스로 물러난다. 신호를 주고받을 필요가 없다.
enum OwnershipHandoff {
    enum Decision: Equatable {
        /// launchd 인스턴스가 떴다. 내가 물러난다.
        case handOff
        /// 아직 안 떴다. 여기서 물러나면 앱이 통째로 사라진다.
        case keepRunning
    }

    /// 재등록 직전 스냅샷에 없던 pid가 생겼는지만 본다. 그 pid가 곧 launchd가 띄운
    /// 인스턴스다 — 우리가 방금 `register()`로 그러도록 시켰기 때문이다.
    static func decide(
        pidsBeforeRegister: Set<pid_t>,
        currentPIDs: Set<pid_t>,
        currentPID: pid_t
    ) -> Decision {
        let newcomers = currentPIDs
            .subtracting(pidsBeforeRegister)
            .subtracting([currentPID])
        return newcomers.isEmpty ? .keepRunning : .handOff
    }
}

/// 자동 시작 등록 상태를 어떻게 맞출지 정하는 순수 함수. 부작용이 없어 전수 테스트가 가능하다.
enum AutoStartPolicy {
    static func action(
        userChoice: Bool?,
        agentStatus: AutoStartStatus,
        mainAppStatus: AutoStartStatus,
        isAgentManaged: Bool
    ) -> AutoStartAction {
        guard let userChoice else {
            // 한 번도 선택한 적 없음 = 신규 설치이거나 업데이트 후 첫 실행. 기본 ON으로 켠다.
            if mainAppStatus.isRegistered {
                return .migrateFromMainApp
            }
            return reconcileEnabled(agentStatus, isAgentManaged: isAgentManaged)
        }

        guard userChoice else {
            // 사용자가 명시적으로 껐다. 어떤 상태에서도 다시 켜지 않는다.
            return agentStatus.isRegistered ? .unregisterAgent : .none
        }

        return reconcileEnabled(agentStatus, isAgentManaged: isAgentManaged)
    }

    /// "켜져 있어야 한다"가 확정된 뒤 현재 상태를 어떻게 맞출지 정한다.
    /// 첫 실행 분기와 자가 치유 분기가 같은 판단을 쓰도록 한 곳에 모았다 —
    /// 어긋나면 한쪽만 실패할 `register()`를 매 기동 반복한다.
    private static func reconcileEnabled(
        _ agentStatus: AutoStartStatus,
        isAgentManaged: Bool
    ) -> AutoStartAction {
        switch agentStatus {
        case .enabled:
            return isAgentManaged ? .none : .reregisterAgent
        case .requiresApproval, .unknown:
            // requiresApproval은 사용자가 시스템 설정에서 껐다는 뜻이라 존중한다.
            // unknown은 우리가 모르는 상태다. 모르면 건드리지 않는다.
            return .none
        case .notRegistered, .notFound:
            // 앱을 옮겼거나 번들이 교체되면 여기로 떨어진다. 자가 치유한다.
            return .registerAgent
        }
    }
}

@MainActor
enum AutoStartRegistration {
    static func reregister(
        unregister: (@escaping @Sendable (Error?) -> Void) -> Void,
        register: () throws -> Void
    ) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            unregister { error in
                if let error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume()
                }
            }
        }
        try register()
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

    /// 기동 시 1회 호출. 기본 ON 적용, 구 로그인 항목 마이그레이션, agent 재등록을 수행한다.
    func applyPolicyAtLaunch(isAgentManaged: Bool) async {
        // DerivedData나 .dmg에서 실행된 빌드는 등록하지 않는다. 등록하면 Xcode의 Stop(SIGKILL)이
        // 비정상 종료로 잡혀 KeepAlive가 개발 빌드를 되살리고, DerivedData를 지우면
        // 시스템 설정에 죽은 로그인 항목이 남는다.
        guard AppInstallLocation.canUseSparkleUpdates() else { return }

        let choice = userChoice
        let action = AutoStartPolicy.action(
            userChoice: choice,
            agentStatus: status,
            mainAppStatus: Self.map(SMAppService.mainApp.status),
            isAgentManaged: isAgentManaged
        )

        // 등록 직전의 인스턴스 목록. 등록이 새로 띄운 프로세스를 이것과의 차집합으로 가린다.
        let pidsBeforeRegister = Set(
            Bundle.main.bundleIdentifier
                .map { SingleInstanceGuard.runningPIDs(forBundleIdentifier: $0) } ?? []
        )
        var didRegister = false

        do {
            switch action {
            case .none:
                break
            case .registerAgent:
                try agent.register()
                didRegister = true
            case .reregisterAgent:
                try await reregisterAgent()
                didRegister = true
            case .unregisterAgent:
                try await agent.unregister()
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
                try await SMAppService.mainApp.unregister()
                didRegister = true
            }

            if choice == nil {
                userChoice = true
            }

            // 내가 launchd가 띄운 프로세스가 아닌데 방금 등록을 했다면, launchd가 새
            // 인스턴스를 띄웠을 것이다. 그쪽이 KeepAlive의 보호를 받는 프로세스이므로
            // 내가 물러나야 한 개만 남고, 그 한 개가 감시 대상이 된다.
            if didRegister && !isAgentManaged {
                await handOffToLaunchdInstance(pidsBeforeRegister: pidsBeforeRegister)
            }
        } catch {
            // 실패하면 userChoice를 저장하지 않는다. 다음 기동에서 다시 시도한다.
            logger.error("auto-start \(String(describing: action), privacy: .public) failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    /// launchd 인스턴스가 뜰 때까지만 기다렸다가 스스로 종료한다.
    ///
    /// 끝내 안 뜨면 **물러나지 않는다.** 등록이 조용히 실패했거나 launchd가 잡을 막은
    /// 상황에서 내가 빠지면 사용자에게 앱이 통째로 사라진다.
    private func handOffToLaunchdInstance(pidsBeforeRegister: Set<pid_t>) async {
        guard let bundleIdentifier = Bundle.main.bundleIdentifier else { return }
        let me = ProcessInfo.processInfo.processIdentifier

        for _ in 0..<Self.handoffMaxChecks {
            let current = Set(SingleInstanceGuard.runningPIDs(forBundleIdentifier: bundleIdentifier))
            if OwnershipHandoff.decide(
                pidsBeforeRegister: pidsBeforeRegister,
                currentPIDs: current,
                currentPID: me
            ) == .handOff {
                logger.notice("handing ownership to the launchd-managed instance; exiting")
                exit(0)
            }
            try? await Task.sleep(nanoseconds: Self.handoffCheckIntervalNanoseconds)
        }

        // 여기 도달하면 등록은 성공했다는데 프로세스가 안 떴다는 뜻이다. 추론 말고 남긴다.
        logger.error("registered the agent but no launchd-managed instance appeared; staying up")
    }

    private static let handoffMaxChecks = 40
    private static let handoffCheckIntervalNanoseconds: UInt64 = 250_000_000

    private func reregisterAgent() async throws {
        let service = agent
        try await AutoStartRegistration.reregister(
            unregister: { completion in service.unregister(completionHandler: completion) },
            register: { try service.register() }
        )
    }
}
