import XCTest

final class UpdaterBehaviorContractTests: XCTestCase {
    func testSparkleChecksAutomaticallyButWaitsForUserApprovalBeforeInstalling() throws {
        let project = try readSourceFile("project.yml")
        let docs = try readSourceFile("AUTO_UPDATE_SETUP.md")

        XCTAssertTrue(project.contains("SUEnableAutomaticChecks: true"))
        XCTAssertTrue(project.contains("SUScheduledCheckInterval: 3600"))
        XCTAssertTrue(project.contains("SUAutomaticallyUpdate: false"))
        XCTAssertTrue(docs.contains("새 버전 감지 → 표준 Sparkle 다이얼로그"))
        XCTAssertTrue(docs.contains("사용자가 승인하면 다운로드/설치/재시작까지 진행"))
    }

    private func readSourceFile(_ relativePath: String) throws -> String {
        let fileName = URL(fileURLWithPath: relativePath).lastPathComponent
        let fileURL = try XCTUnwrap(Bundle(for: Self.self).resourceURL?.appendingPathComponent(fileName))

        return try String(contentsOf: fileURL, encoding: .utf8)
    }
}
