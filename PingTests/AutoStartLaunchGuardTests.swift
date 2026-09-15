import XCTest
@testable import Ping

final class AutoStartLaunchGuardTests: XCTestCase {
    func testProceedsWhenNoOtherInstanceExists() {
        XCTAssertEqual(
            SingleInstanceGuard.action(runningPIDs: [42], currentPID: 42, isAgentManaged: false),
            .proceed
        )
    }

    func testProceedsWhenLaunchServicesHasNotListedTheCurrentProcessYet() {
        // LaunchServices 등록 전이면 자기 자신도 목록에 없을 수 있다. 물러나면 앱이 아예 안 뜬다.
        XCTAssertEqual(
            SingleInstanceGuard.action(runningPIDs: [], currentPID: 42, isAgentManaged: false),
            .proceed
        )
    }

    func testUnmanagedDuplicateYieldsToExistingInstance() {
        XCTAssertEqual(
            SingleInstanceGuard.action(runningPIDs: [17, 42], currentPID: 42, isAgentManaged: false),
            .yield
        )
    }

    func testManagedDuplicateReplacesExistingInstance() {
        XCTAssertEqual(
            SingleInstanceGuard.action(runningPIDs: [17, 42], currentPID: 42, isAgentManaged: true),
            .replaceExisting([17])
        )
    }

    func testRecognizesOnlyTheKeepAliveServiceNameAsManaged() {
        XCTAssertTrue(PingLaunchOrigin.isAgentManaged(environment: [
            "XPC_SERVICE_NAME": "com.youngminpark.ping.Ping.keepalive"
        ]))
        XCTAssertFalse(PingLaunchOrigin.isAgentManaged(environment: [
            "XPC_SERVICE_NAME": "application.com.youngminpark.ping.Ping.random"
        ]))
        XCTAssertFalse(PingLaunchOrigin.isAgentManaged(environment: [:]))
    }

    func testLocatorReturnsEmptyForUnknownBundleIdentifier() {
        let pids = SingleInstanceGuard.runningPIDs(forBundleIdentifier: "com.youngminpark.ping.NoSuchApp")

        XCTAssertTrue(pids.isEmpty)
    }

    // MARK: 기동 훅 계약

    func testAppDelegateYieldsBeforeDoingAnythingElse() throws {
        let source = try readSourceFile("AppDelegate.swift")

        XCTAssertTrue(source.contains("SingleInstanceGuard.action"))
        // exit(0)이어야 launchd가 비정상 종료로 보지 않아 재실행하지 않는다.
        XCTAssertTrue(source.contains("exit(0)"))
        XCTAssertTrue(source.contains("case .replaceExisting(let pids)"))
        // terminate()는 quit 이벤트를 보냈다는 뜻일 뿐이라, 기동 중인 대상은 그걸 흘린다.
        // 확인과 강제 폴백까지 있어야 중복 인스턴스가 실제로 사라진다.
        XCTAssertTrue(source.contains("DuplicateInstanceTerminator.replace("))
        XCTAssertTrue(source.contains("?.terminate()"))
        XCTAssertTrue(source.contains("?.forceTerminate()"))

        let guardIndex = try XCTUnwrap(source.range(of: "switch singleInstanceAction()")?.lowerBound)
        let activationIndex = try XCTUnwrap(source.range(of: "enforceAccessoryActivationPolicy()")?.lowerBound)
        let setupIndex = try XCTUnwrap(source.range(of: "setupStatusBar()")?.lowerBound)
        XCTAssertLessThan(guardIndex, activationIndex)
        XCTAssertLessThan(activationIndex, setupIndex)
    }

    func testAppDelegateAppliesAutoStartPolicyAtLaunch() throws {
        let source = try readSourceFile("AppDelegate.swift")

        // 이 호출이 빠지면 기능 전체가 조용히 동작을 멈추고 단위 테스트는 전부 통과한다.
        XCTAssertTrue(source.contains("AutoStartController.shared.applyPolicyAtLaunch("))
        XCTAssertTrue(source.contains("isAgentManaged: isAgentManagedProcess"))
    }

    private func readSourceFile(_ relativePath: String) throws -> String {
        try String(contentsOf: resourceURL(for: relativePath), encoding: .utf8)
    }

    private func resourceURL(for relativePath: String) throws -> URL {
        let fileName = URL(fileURLWithPath: relativePath).lastPathComponent
        return try XCTUnwrap(Bundle(for: Self.self).resourceURL?.appendingPathComponent(fileName))
    }
}

/// `.replaceExisting`이 소유권 이전을 끝까지 완수하는지 검증한다.
///
/// 회귀 배경: `NSRunningApplication.terminate()`는 quit 이벤트를 보냈다는 뜻일 뿐이라,
/// 기동 직후라 아직 이벤트 루프가 없는 전임자는 그걸 흘린다. 확인도 재시도도 없던 탓에
/// launchd가 띄운 인스턴스와 전임자가 둘 다 살아남았다 — 창이 두 개 열리던 증상이다.
final class DuplicateInstanceTerminatorTests: XCTestCase {
    func testDoesNothingWhenPredecessorsAreAlreadyGone() {
        var politeCalls: [pid_t] = []
        var forceCalls: [pid_t] = []
        var waits = 0

        let forced = DuplicateInstanceTerminator.replace(
            pids: [101, 102],
            politeQuit: { politeCalls.append($0) },
            hasExited: { _ in true },
            forceQuit: { forceCalls.append($0) },
            waitStep: { waits += 1 },
            maxChecks: 8
        )

        XCTAssertEqual(politeCalls, [])
        XCTAssertEqual(forceCalls, [])
        XCTAssertEqual(waits, 0)
        XCTAssertEqual(forced, [])
    }

    /// 핵심 회귀 방지: 첫 요청이 흘러가도 다음 회차에 다시 요청해야 한다.
    /// 한 번만 보내고 기다리면 남는 결말은 강제 종료뿐이다.
    func testReissuesPoliteQuitEachRoundUntilPredecessorExits() {
        var politeCalls: [pid_t] = []
        var forceCalls: [pid_t] = []
        var waits = 0
        var probes = 0

        let forced = DuplicateInstanceTerminator.replace(
            pids: [101],
            politeQuit: { politeCalls.append($0) },
            hasExited: { _ in
                probes += 1
                return probes > 2
            },
            forceQuit: { forceCalls.append($0) },
            waitStep: { waits += 1 },
            maxChecks: 8
        )

        XCTAssertEqual(politeCalls, [101, 101], "회차마다 다시 요청해야 한다")
        XCTAssertEqual(forceCalls, [], "정중한 요청이 먹혔으면 강제하지 않는다")
        XCTAssertEqual(waits, 2)
        XCTAssertEqual(forced, [])
    }

    func testForcesOnlyAfterTheDeadline() {
        var politeCalls: [pid_t] = []
        var forceCalls: [pid_t] = []
        var waits = 0

        let forced = DuplicateInstanceTerminator.replace(
            pids: [101],
            politeQuit: { politeCalls.append($0) },
            hasExited: { _ in false },
            forceQuit: { forceCalls.append($0) },
            waitStep: { waits += 1 },
            maxChecks: 4
        )

        XCTAssertEqual(politeCalls, [101, 101, 101, 101])
        XCTAssertEqual(waits, 4)
        XCTAssertEqual(forceCalls, [101], "기한을 넘긴 뒤에만 강제한다")
        XCTAssertEqual(forced, [101], "강제까지 간 pid를 돌려줘야 호출부가 계측할 수 있다")
    }

    func testForcesOnlyTheSurvivors() {
        var politeCalls: [pid_t] = []
        var forceCalls: [pid_t] = []

        let forced = DuplicateInstanceTerminator.replace(
            pids: [101, 102],
            politeQuit: { politeCalls.append($0) },
            hasExited: { $0 == 101 },
            forceQuit: { forceCalls.append($0) },
            waitStep: {},
            maxChecks: 3
        )

        XCTAssertFalse(politeCalls.contains(101), "이미 죽은 프로세스에는 요청하지 않는다")
        XCTAssertEqual(Set(politeCalls), [102])
        XCTAssertEqual(forceCalls, [102])
        XCTAssertEqual(forced, [102])
    }

    func testEmptyInputDoesNothing() {
        var politeCalls = 0
        let forced = DuplicateInstanceTerminator.replace(
            pids: [],
            politeQuit: { _ in politeCalls += 1 },
            hasExited: { _ in false },
            forceQuit: { _ in },
            waitStep: {},
            maxChecks: 8
        )
        XCTAssertEqual(politeCalls, 0)
        XCTAssertEqual(forced, [])
    }
}

/// 소유권을 **내가 물러나는 방식**으로 넘기는지 검증한다.
///
/// 회귀 배경: 원래 설계는 신참이 전임자에게 종료를 요청하는 것이었는데, 그 요청은
/// 샌드박스에서 전달되지 않는다(`terminate()`는 quit AppleEvent이고 Ping에는
/// `com.apple.security.automation.apple-events` 권한이 없다). 0.3.75까지 중복
/// 인스턴스가 그대로 남은 이유다.
final class OwnershipHandoffTests: XCTestCase {
    func testHandsOffWhenRegistrationStartedANewInstance() {
        let decision = OwnershipHandoff.decide(
            pidsBeforeRegister: [100],
            currentPIDs: [100, 200],
            currentPID: 100
        )
        XCTAssertEqual(decision, .handOff)
    }

    /// 안 떴는데 물러나면 사용자에게 앱이 통째로 사라진다. 등록이 조용히 실패했거나
    /// launchd가 잡을 막은 경우가 여기 해당한다.
    func testKeepsRunningWhenNoNewInstanceAppeared() {
        let decision = OwnershipHandoff.decide(
            pidsBeforeRegister: [100],
            currentPIDs: [100],
            currentPID: 100
        )
        XCTAssertEqual(decision, .keepRunning)
    }

    func testMyOwnPidIsNeverMistakenForTheNewcomer() {
        // 등록 직전 스냅샷에 내가 빠져 있어도(경쟁 상황) 나를 신참으로 세면 안 된다.
        let decision = OwnershipHandoff.decide(
            pidsBeforeRegister: [],
            currentPIDs: [100],
            currentPID: 100
        )
        XCTAssertEqual(decision, .keepRunning)
    }

    func testPreexistingInstancesAreNotNewcomers() {
        let decision = OwnershipHandoff.decide(
            pidsBeforeRegister: [100, 300],
            currentPIDs: [100, 300],
            currentPID: 100
        )
        XCTAssertEqual(decision, .keepRunning)
    }

    func testHandsOffEvenWhenAnOlderInstanceAlsoLingers() {
        let decision = OwnershipHandoff.decide(
            pidsBeforeRegister: [100, 300],
            currentPIDs: [100, 300, 400],
            currentPID: 100
        )
        XCTAssertEqual(decision, .handOff)
    }
}

/// 핸드오프가 실제로 배선돼 있는지 잠근다. 이 호출이 빠지면 중복 인스턴스가 조용히
/// 돌아오고 유닛 테스트는 전부 통과한다 — 0.3.75에서 실제로 그랬다.
final class OwnershipHandoffWiringTests: XCTestCase {
    func testControllerHandsOffAfterRegisteringWhileUnmanaged() throws {
        let source = try String(
            contentsOf: URL(fileURLWithPath: #filePath)
                .deletingLastPathComponent()
                .deletingLastPathComponent()
                .appendingPathComponent("Ping/Core/AutoStart.swift"),
            encoding: .utf8
        )

        XCTAssertTrue(source.contains("handOffToLaunchdInstance("))
        XCTAssertTrue(
            source.contains("if didRegister && !isAgentManaged {"),
            "등록을 했고 내가 launchd 프로세스가 아닐 때만 물러나야 한다"
        )
        XCTAssertTrue(
            source.contains("exit(0)"),
            "물러남은 정상 종료여야 한다. 비정상 종료면 KeepAlive가 나를 되살린다"
        )
    }
}
