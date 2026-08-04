import ServiceManagement
import XCTest
@testable import Ping

final class AutoStartPolicyTests: XCTestCase {
    private let allStatuses: [AutoStartStatus] = [.enabled, .requiresApproval, .notRegistered, .notFound, .unknown]

    // MARK: userChoice == nil — 기본 ON

    func testFirstRunRegistersAgent() {
        let action = AutoStartPolicy.action(
            userChoice: nil,
            agentStatus: .notRegistered,
            mainAppStatus: .notRegistered
        )

        XCTAssertEqual(action, .registerAgent)
    }

    func testFirstRunMigratesWhenLegacyLoginItemIsEnabled() {
        for mainAppStatus in [AutoStartStatus.enabled, .requiresApproval] {
            let action = AutoStartPolicy.action(
                userChoice: nil,
                agentStatus: .notRegistered,
                mainAppStatus: mainAppStatus
            )

            XCTAssertEqual(action, .migrateFromMainApp, "mainAppStatus: \(mainAppStatus)")
        }
    }

    func testFirstRunDoesNothingWhenAgentIsAlreadyEnabled() {
        let action = AutoStartPolicy.action(
            userChoice: nil,
            agentStatus: .enabled,
            mainAppStatus: .notRegistered
        )

        XCTAssertEqual(action, .none)
    }

    func testFirstRunRespectsSystemSettingsApprovalState() {
        // 사용자가 시스템 설정에서 껐다면 첫 실행에서도 억지로 다시 켜지 않는다.
        // 재시도하면 매 기동마다 실패할 register()를 영원히 반복하고 userChoice도 저장되지 않는다.
        let action = AutoStartPolicy.action(
            userChoice: nil,
            agentStatus: .requiresApproval,
            mainAppStatus: .notRegistered
        )

        XCTAssertEqual(action, .none)
    }

    func testFirstRunBranchIsSymmetricWithSelfHealBranch() {
        // nil 분기와 true 분기가 같은 agentStatus에 대해 같은 판단을 내려야 한다.
        // 어긋나면 한쪽만 무한 재시도에 빠진다.
        for agentStatus in allStatuses {
            let firstRun = AutoStartPolicy.action(
                userChoice: nil,
                agentStatus: agentStatus,
                mainAppStatus: .notRegistered
            )
            let selfHeal = AutoStartPolicy.action(
                userChoice: true,
                agentStatus: agentStatus,
                mainAppStatus: .notRegistered
            )

            XCTAssertEqual(firstRun, selfHeal, "agentStatus: \(agentStatus)")
        }
    }

    // MARK: userChoice == true — 자가 치유

    func testEnabledChoiceReregistersWhenAgentIsMissing() {
        for agentStatus in [AutoStartStatus.notRegistered, .notFound] {
            let action = AutoStartPolicy.action(
                userChoice: true,
                agentStatus: agentStatus,
                mainAppStatus: .notRegistered
            )

            XCTAssertEqual(action, .registerAgent, "agentStatus: \(agentStatus)")
        }
    }

    func testEnabledChoiceRespectsSystemSettingsApprovalState() {
        // requiresApproval은 사용자가 시스템 설정에서 껐다는 뜻이다. 억지로 다시 켜지 않는다.
        let action = AutoStartPolicy.action(
            userChoice: true,
            agentStatus: .requiresApproval,
            mainAppStatus: .notRegistered
        )

        XCTAssertEqual(action, .none)
    }

    // MARK: userChoice == false — 절대 뒤집지 않는다

    func testDisabledChoiceNeverRegisters() {
        for agentStatus in allStatuses {
            for mainAppStatus in allStatuses {
                let action = AutoStartPolicy.action(
                    userChoice: false,
                    agentStatus: agentStatus,
                    mainAppStatus: mainAppStatus
                )

                XCTAssertNotEqual(action, .registerAgent, "\(agentStatus)/\(mainAppStatus)")
                XCTAssertNotEqual(action, .migrateFromMainApp, "\(agentStatus)/\(mainAppStatus)")
            }
        }
    }

    func testDisabledChoiceUnregistersOnlyWhenRegistered() {
        XCTAssertEqual(
            AutoStartPolicy.action(userChoice: false, agentStatus: .enabled, mainAppStatus: .notRegistered),
            .unregisterAgent
        )
        XCTAssertEqual(
            AutoStartPolicy.action(userChoice: false, agentStatus: .notRegistered, mainAppStatus: .notRegistered),
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
                    mainAppStatus: mainAppStatus
                )
                let withoutLegacy = AutoStartPolicy.action(
                    userChoice: userChoice,
                    agentStatus: .enabled,
                    mainAppStatus: .notRegistered
                )

                XCTAssertEqual(withLegacy, withoutLegacy, "\(userChoice)/\(mainAppStatus)")
            }
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
