import XCTest

final class AutoStartSettingsWiringTests: XCTestCase {
    func testToggleDrivesKeepAliveAgentInsteadOfLoginItem() throws {
        let source = try readSourceFile("SettingsScene.swift")

        // mainApp을 남겨두면 agent와 함께 등록돼 로그인 시 두 번 실행된다.
        XCTAssertFalse(source.contains("SMAppService.mainApp"))
        XCTAssertTrue(source.contains("AutoStartController.shared.setEnabled"))
    }

    func testSettingsCopyIsUnchanged() throws {
        let source = try readSourceFile("SettingsScene.swift")

        XCTAssertTrue(source.contains("title: \"로그인 시 자동 시작\""))
        XCTAssertTrue(source.contains("\"켜져 있음\""))
        XCTAssertTrue(source.contains("\"시스템 설정에서 승인이 필요합니다.\""))
        XCTAssertTrue(source.contains("\"꺼져 있음\""))
        XCTAssertTrue(source.contains("\"자동 시작 항목을 찾을 수 없습니다.\""))
        XCTAssertTrue(source.contains("\"상태를 확인할 수 없습니다.\""))
        XCTAssertTrue(source.contains("\"자동 시작 설정을 변경하지 못했습니다.\""))
    }

    private func readSourceFile(_ relativePath: String) throws -> String {
        try String(contentsOf: resourceURL(for: relativePath), encoding: .utf8)
    }

    private func resourceURL(for relativePath: String) throws -> URL {
        let fileName = URL(fileURLWithPath: relativePath).lastPathComponent
        return try XCTUnwrap(Bundle(for: Self.self).resourceURL?.appendingPathComponent(fileName))
    }
}
