import ServiceManagement
import XCTest
@testable import Ping

final class AutoStartPolicyTests: XCTestCase {
    private enum StubError: Error, Equatable {
        case unregister
        case register
    }

    private let allStatuses: [AutoStartStatus] = [.enabled, .requiresApproval, .notRegistered, .notFound, .unknown]

    // MARK: userChoice == nil — 기본 ON

    func testFirstRunRegistersAgent() {
        let action = AutoStartPolicy.action(
            userChoice: nil,
            agentStatus: .notRegistered,
            mainAppStatus: .notRegistered,
            isAgentManaged: true
        )

        XCTAssertEqual(action, .registerAgent)
    }

    func testFirstRunMigratesWhenLegacyLoginItemIsEnabled() {
        for mainAppStatus in [AutoStartStatus.enabled, .requiresApproval] {
            let action = AutoStartPolicy.action(
                userChoice: nil,
                agentStatus: .notRegistered,
                mainAppStatus: mainAppStatus,
                isAgentManaged: true
            )

            XCTAssertEqual(action, .migrateFromMainApp, "mainAppStatus: \(mainAppStatus)")
        }
    }

    func testFirstRunDoesNothingWhenAgentIsAlreadyEnabled() {
        let action = AutoStartPolicy.action(
            userChoice: nil,
            agentStatus: .enabled,
            mainAppStatus: .notRegistered,
            isAgentManaged: true
        )

        XCTAssertEqual(action, .none)
    }

    func testFirstRunRespectsSystemSettingsApprovalState() {
        // 사용자가 시스템 설정에서 껐다면 첫 실행에서도 억지로 다시 켜지 않는다.
        // 재시도하면 매 기동마다 실패할 register()를 영원히 반복하고 userChoice도 저장되지 않는다.
        let action = AutoStartPolicy.action(
            userChoice: nil,
            agentStatus: .requiresApproval,
            mainAppStatus: .notRegistered,
            isAgentManaged: true
        )

        XCTAssertEqual(action, .none)
    }

    func testFirstRunBranchIsSymmetricWithSelfHealBranch() {
        // nil 분기와 true 분기가 같은 agentStatus에 대해 같은 판단을 내려야 한다.
        // 어긋나면 한쪽만 무한 재시도에 빠진다.
        for isAgentManaged in [true, false] {
            for agentStatus in allStatuses {
                let firstRun = AutoStartPolicy.action(
                    userChoice: nil,
                    agentStatus: agentStatus,
                    mainAppStatus: .notRegistered,
                    isAgentManaged: isAgentManaged
                )
                let selfHeal = AutoStartPolicy.action(
                    userChoice: true,
                    agentStatus: agentStatus,
                    mainAppStatus: .notRegistered,
                    isAgentManaged: isAgentManaged
                )

                XCTAssertEqual(
                    firstRun,
                    selfHeal,
                    "agentStatus: \(agentStatus), isAgentManaged: \(isAgentManaged)"
                )
            }
        }
    }

    // MARK: userChoice == true — 자가 치유

    func testEnabledChoiceReregistersWhenAgentIsMissing() {
        for agentStatus in [AutoStartStatus.notRegistered, .notFound] {
            let action = AutoStartPolicy.action(
                userChoice: true,
                agentStatus: agentStatus,
                mainAppStatus: .notRegistered,
                isAgentManaged: true
            )

            XCTAssertEqual(action, .registerAgent, "agentStatus: \(agentStatus)")
        }
    }

    func testEnabledChoiceRespectsSystemSettingsApprovalState() {
        // requiresApproval은 사용자가 시스템 설정에서 껐다는 뜻이다. 억지로 다시 켜지 않는다.
        let action = AutoStartPolicy.action(
            userChoice: true,
            agentStatus: .requiresApproval,
            mainAppStatus: .notRegistered,
            isAgentManaged: true
        )

        XCTAssertEqual(action, .none)
    }

    // MARK: userChoice == false — 절대 뒤집지 않는다

    func testDisabledChoiceNeverRegisters() {
        for isAgentManaged in [true, false] {
            for agentStatus in allStatuses {
                for mainAppStatus in allStatuses {
                    let action = AutoStartPolicy.action(
                        userChoice: false,
                        agentStatus: agentStatus,
                        mainAppStatus: mainAppStatus,
                        isAgentManaged: isAgentManaged
                    )

                    let context = "\(agentStatus)/\(mainAppStatus)/\(isAgentManaged)"
                    XCTAssertNotEqual(action, .registerAgent, context)
                    XCTAssertNotEqual(action, .reregisterAgent, context)
                    XCTAssertNotEqual(action, .migrateFromMainApp, context)
                }
            }
        }
    }

    func testDisabledChoiceUnregistersOnlyWhenRegistered() {
        XCTAssertEqual(
            AutoStartPolicy.action(
                userChoice: false,
                agentStatus: .enabled,
                mainAppStatus: .notRegistered,
                isAgentManaged: true
            ),
            .unregisterAgent
        )
        XCTAssertEqual(
            AutoStartPolicy.action(
                userChoice: false,
                agentStatus: .notRegistered,
                mainAppStatus: .notRegistered,
                isAgentManaged: true
            ),
            .none
        )
    }

    // MARK: 마이그레이션은 1회성

    func testLegacyLoginItemIsIgnoredOnceUserChoiceExists() {
        for userChoice in [true, false] {
            for mainAppStatus in allStatuses {
                let withLegacy = AutoStartPolicy.action(
                    userChoice: userChoice,
                    agentStatus: .enabled,
                    mainAppStatus: mainAppStatus,
                    isAgentManaged: true
                )
                let withoutLegacy = AutoStartPolicy.action(
                    userChoice: userChoice,
                    agentStatus: .enabled,
                    mainAppStatus: .notRegistered,
                    isAgentManaged: true
                )

                XCTAssertEqual(withLegacy, withoutLegacy, "\(userChoice)/\(mainAppStatus)")
            }
        }
    }

    // MARK: 재등록은 등록이 실제로 낡았을 때만

    /// 사용자가 직접 실행하거나 macOS가 로그인 때 복원하면 agent가 띄운 게 아니게 된다.
    /// 예전엔 그것만으로 재등록했고, `register()`가 `RunAtLoad`로 두 번째 인스턴스를
    /// 낳아 창이 두 개 열렸다. 등록이 지금 번들을 가리키면 아무것도 하지 않아야 한다.
    func testEnabledUnmanagedLaunchDoesNotRefreshWhenRegistrationMatchesBundle() {
        XCTAssertEqual(
            AutoStartPolicy.action(
                userChoice: true,
                agentStatus: .enabled,
                mainAppStatus: .notRegistered,
                isAgentManaged: false,
                registrationIsStale: false
            ),
            .none
        )
    }

    /// 앱을 옮기면 등록이 옛 경로를 가리킨다. 이때는 자가 치유해야 한다.
    func testEnabledUnmanagedLaunchRefreshesWhenRegistrationIsStale() {
        XCTAssertEqual(
            AutoStartPolicy.action(
                userChoice: true,
                agentStatus: .enabled,
                mainAppStatus: .notRegistered,
                isAgentManaged: false,
                registrationIsStale: true
            ),
            .reregisterAgent
        )
    }

    /// agent가 띄운 인스턴스는 등록이 살아 있다는 증거다. 낡았다는 신호가 있어도
    /// 그 프로세스가 곧 반증이므로 재등록해서 자기 복제를 만들면 안 된다.
    func testAgentManagedLaunchNeverRefreshesEvenWhenFlaggedStale() {
        XCTAssertEqual(
            AutoStartPolicy.action(
                userChoice: true,
                agentStatus: .enabled,
                mainAppStatus: .notRegistered,
                isAgentManaged: true,
                registrationIsStale: true
            ),
            .none
        )
    }

    func testEnabledManagedLaunchDoesNotRefreshAgent() {
        XCTAssertEqual(
            AutoStartPolicy.action(
                userChoice: true,
                agentStatus: .enabled,
                mainAppStatus: .notRegistered,
                isAgentManaged: true
            ),
            .none
        )
    }

    @MainActor
    func testReregisterWaitsForUnregisterBeforeRegistering() async throws {
        var events: [String] = []

        try await AutoStartRegistration.reregister(
            unregister: { completion in
                events.append("unregister")
                completion(nil)
            },
            register: {
                events.append("register")
            }
        )

        XCTAssertEqual(events, ["unregister", "register"])
    }

    @MainActor
    func testReregisterDoesNotRegisterWhenUnregisterFails() async {
        var didRegister = false

        do {
            try await AutoStartRegistration.reregister(
                unregister: { completion in completion(StubError.unregister) },
                register: { didRegister = true }
            )
            XCTFail("Expected unregister failure")
        } catch {
            XCTAssertEqual(error as? StubError, .unregister)
        }

        XCTAssertFalse(didRegister)
    }

    @MainActor
    func testReregisterPropagatesRegisterFailure() async {
        do {
            try await AutoStartRegistration.reregister(
                unregister: { completion in completion(nil) },
                register: { throw StubError.register }
            )
            XCTFail("Expected register failure")
        } catch {
            XCTAssertEqual(error as? StubError, .register)
        }
    }

    // MARK: 컨트롤러

    @MainActor
    func testUserChoiceRoundTripsAndDistinguishesFalseFromUnset() {
        let suiteName = "AutoStartPolicyTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let controller = AutoStartController(defaults: defaults)
        XCTAssertNil(controller.userChoice)

        controller.userChoice = true
        XCTAssertEqual(controller.userChoice, true)

        // bool(forKey:)로 읽으면 false와 미설정이 뭉개져 사용자가 끈 상태가 매 기동마다 다시 켜진다.
        controller.userChoice = false
        XCTAssertEqual(controller.userChoice, false)
        XCTAssertNotNil(controller.userChoice)
    }

    @MainActor
    func testStatusMappingCoversEveryServiceManagementCase() {
        XCTAssertEqual(AutoStartController.map(.enabled), .enabled)
        XCTAssertEqual(AutoStartController.map(.requiresApproval), .requiresApproval)
        XCTAssertEqual(AutoStartController.map(.notRegistered), .notRegistered)
        XCTAssertEqual(AutoStartController.map(.notFound), .notFound)
    }

    @MainActor
    func testAgentPlistNameMatchesBundledFile() {
        XCTAssertEqual(
            AutoStartController.agentPlistName,
            "com.youngminpark.ping.Ping.keepalive.plist"
        )
    }

    func testPreferenceKeyIsStable() {
        XCTAssertEqual(PingPreferenceKeys.autostartUserChoice, "ping.autostart.userChoice")
    }
}
