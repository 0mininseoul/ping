import XCTest
@testable import Ping

final class AutoStartLaunchGuardTests: XCTestCase {
    func testDoesNotYieldWhenAloneInTheList() {
        XCTAssertFalse(SingleInstanceGuard.shouldYield(runningPIDs: [42], currentPID: 42))
    }

    func testDoesNotYieldWhenListIsEmpty() {
        // LaunchServices 등록 전이면 자기 자신도 목록에 없을 수 있다. 물러나면 앱이 아예 안 뜬다.
        XCTAssertFalse(SingleInstanceGuard.shouldYield(runningPIDs: [], currentPID: 42))
    }

    func testYieldsWhenAnotherInstanceIsAlreadyRunning() {
        XCTAssertTrue(SingleInstanceGuard.shouldYield(runningPIDs: [17, 42], currentPID: 42))
    }

    func testYieldsEvenWhenSelfIsNotYetListed() {
        XCTAssertTrue(SingleInstanceGuard.shouldYield(runningPIDs: [17], currentPID: 42))
    }

    func testLocatorReturnsEmptyForUnknownBundleIdentifier() {
        let pids = SingleInstanceGuard.runningPIDs(forBundleIdentifier: "com.youngminpark.ping.NoSuchApp")

        XCTAssertTrue(pids.isEmpty)
    }

    // MARK: 기동 훅 계약

    func testAppDelegateYieldsBeforeDoingAnythingElse() throws {
        let source = try readSourceFile("AppDelegate.swift")

        XCTAssertTrue(source.contains("SingleInstanceGuard.shouldYield"))
        // exit(0)이어야 launchd가 비정상 종료로 보지 않아 재실행하지 않는다.
        XCTAssertTrue(source.contains("exit(0)"))
    }

    func testAppDelegateAppliesAutoStartPolicyAtLaunch() throws {
        let source = try readSourceFile("AppDelegate.swift")

        // 이 호출이 빠지면 기능 전체가 조용히 동작을 멈추고 단위 테스트는 전부 통과한다.
        XCTAssertTrue(source.contains("AutoStartController.shared.applyPolicyAtLaunch()"))
    }

    private func readSourceFile(_ relativePath: String) throws -> String {
        try String(contentsOf: resourceURL(for: relativePath), encoding: .utf8)
    }

    private func resourceURL(for relativePath: String) throws -> URL {
        let fileName = URL(fileURLWithPath: relativePath).lastPathComponent
        return try XCTUnwrap(Bundle(for: Self.self).resourceURL?.appendingPathComponent(fileName))
    }
}
