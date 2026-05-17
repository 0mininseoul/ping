import XCTest

final class PermissionUXContractTests: XCTestCase {
    func testPermissionStepRemovesNoOpRecheckButtonAfterAllPermissionsAreGranted() throws {
        let source = try readSourceFile("Ping/UI/Setup/PairingView.swift")

        XCTAssertFalse(source.contains("권한 다시 확인"))
    }

    func testPermissionStepGuidesDeniedPermissionsToSystemSettings() throws {
        let viewSource = try readSourceFile("Ping/UI/Setup/PairingView.swift")
        let viewModelSource = try readSourceFile("Ping/UI/Setup/PairingViewModel.swift")

        XCTAssertTrue(viewSource.contains("시스템 설정 열기"))
        XCTAssertTrue(viewModelSource.contains("openSystemPermissionSettings"))
    }

    func testDeniedPermissionNoticeDoesNotImplyTheUserAlreadyAllowedIt() throws {
        let source = try readSourceFile("Ping/UI/Setup/PairingViewModel.swift")

        XCTAssertFalse(source.contains("시스템 설정에서 다시 켜야 합니다"))
        XCTAssertTrue(source.contains("시스템 설정에서 켜야 합니다"))
    }

    func testPermissionFeedbackDoesNotUseRawYellowText() throws {
        let source = try readSourceFile("Ping/UI/Setup/PairingView.swift")

        XCTAssertFalse(source.contains("Color.yellow"))
    }

    private func readSourceFile(_ relativePath: String) throws -> String {
        let fileName = URL(fileURLWithPath: relativePath).lastPathComponent
        let fileURL = try XCTUnwrap(Bundle(for: Self.self).resourceURL?.appendingPathComponent(fileName))

        return try String(contentsOf: fileURL, encoding: .utf8)
    }
}
