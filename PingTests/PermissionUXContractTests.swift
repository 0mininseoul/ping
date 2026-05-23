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

    func testOnboardingHeaderUsesFixedProgressGaugeLayout() throws {
        let source = try readSourceFile("Ping/UI/Setup/PairingView.swift")

        XCTAssertTrue(source.contains("static let headerHeight"))
        XCTAssertTrue(source.contains(".frame(height: Layout.headerHeight, alignment: .top)"))
        XCTAssertTrue(source.contains("onboardingProgressBar(progress: viewModel.progress)"))
        XCTAssertTrue(source.contains(".scaleEffect(x: min(max(progress, 0), 1), y: 1, anchor: .leading)"))
    }

    func testPermissionStepUsesCompactChecklistAndExplicitScreenSettingsAction() throws {
        let source = try readSourceFile("Ping/UI/Setup/PairingView.swift")

        XCTAssertTrue(source.contains("private var permissionStepHeader"))
        XCTAssertTrue(source.contains("viewModel.grantedPermissionCount"))
        XCTAssertTrue(source.contains("actionTitle: \"설정 열기\""))
        XCTAssertTrue(source.contains("permissionStatusPill(blocked ? \"필요\" : \"대기\""))
    }

    func testNotificationRequestHasVisibleFallbackWhenSystemPromptDoesNotAppear() throws {
        let source = try readSourceFile("Ping/UI/Setup/PairingViewModel.swift")

        XCTAssertTrue(source.contains("NSApp.activate(ignoringOtherApps: true)"))
        XCTAssertTrue(source.contains("알림 허용 창이 보이지 않으면 시스템 설정 > 알림에서 Ping을 켜주세요."))
    }

    private func readSourceFile(_ relativePath: String) throws -> String {
        let fileName = URL(fileURLWithPath: relativePath).lastPathComponent
        let fileURL = try XCTUnwrap(Bundle(for: Self.self).resourceURL?.appendingPathComponent(fileName))

        return try String(contentsOf: fileURL, encoding: .utf8)
    }
}
