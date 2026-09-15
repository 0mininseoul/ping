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
        XCTAssertTrue(source.contains("NSRunningApplication(processIdentifier: pid)?.terminate()"))

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
