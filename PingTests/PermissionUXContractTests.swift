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
        XCTAssertTrue(source.contains("설정 확인 필요"))
    }

    func testPermissionFeedbackDoesNotUseRawYellowText() throws {
        let source = try readSourceFile("Ping/UI/Setup/PairingView.swift")

        XCTAssertFalse(source.contains("Color.yellow"))
    }

    func testOnboardingHeaderUsesFixedProgressGaugeLayout() throws {
        let source = try readSourceFile("Ping/UI/Setup/PairingView.swift")

        XCTAssertTrue(source.contains("static let headerHeight"))
        XCTAssertTrue(source.contains("static let contentHeight"))
        XCTAssertTrue(source.contains(".frame(width: Layout.contentWidth, height: Layout.headerHeight, alignment: .top)"))
        XCTAssertTrue(source.contains(".frame(width: Layout.contentWidth, height: Layout.contentHeight, alignment: .top)"))
        XCTAssertTrue(source.contains("onboardingProgressBar(progress: viewModel.progress)"))
        XCTAssertTrue(source.contains(".scaleEffect(x: min(max(progress, 0), 1), y: 1, anchor: .leading)"))
    }

    func testPermissionStepUsesMinimalChecklistWithoutCounterOrDetailCopy() throws {
        let source = try readSourceFile("Ping/UI/Setup/PairingView.swift")

        XCTAssertTrue(source.contains("private var permissionStepHeader"))
        XCTAssertTrue(source.contains("Text(\"권한 허용\")"))
        XCTAssertTrue(source.contains("private func permissionActionTitle"))
        XCTAssertFalse(source.contains("viewModel.grantedPermissionCount"))
        XCTAssertFalse(source.contains("permissionStatusPill"))
        XCTAssertFalse(source.contains("보내기와 받기에 필요한 항목만 켭니다"))
        XCTAssertFalse(source.contains("\"/ 4\""))
    }

    func testPermissionStepAllowsContinuingToTheRestOfOnboarding() throws {
        let viewSource = try readSourceFile("Ping/UI/Setup/PairingView.swift")
        let viewModelSource = try readSourceFile("Ping/UI/Setup/PairingViewModel.swift")

        XCTAssertTrue(viewSource.contains("viewModel.allPermissionsGranted ? \"다음\" : \"계속\""))
        XCTAssertTrue(viewModelSource.contains("var allPermissionsGranted"))
        XCTAssertTrue(viewModelSource.contains("var canProceedFromPermissions: Bool {\n        true\n    }"))
    }

    func testMediaPermissionRequestsDoNotLeaveTheRowStuckForever() throws {
        let source = try readSourceFile("Ping/UI/Setup/PairingViewModel.swift")

        XCTAssertTrue(source.contains("requestMediaAccessWithTimeout"))
        XCTAssertTrue(source.contains("DispatchQueue.main.asyncAfter(deadline: .now() + 10)"))
    }

    func testNotificationRequestHasVisibleFallbackWhenSystemPromptDoesNotAppear() throws {
        let source = try readSourceFile("Ping/UI/Setup/PairingViewModel.swift")

        XCTAssertTrue(source.contains("NSApp.activate(ignoringOtherApps: true)"))
        XCTAssertTrue(source.contains("알림 허용 창이 보이지 않으면 시스템 설정 > 알림에서 Ping을 켜주세요."))
    }

    func testAppLaunchDoesNotConsumeNotificationPermissionPromptBeforeOnboarding() throws {
        let appDelegateSource = try readSourceFile("Ping/AppDelegate.swift")
        let notificationSource = try readSourceFile("Ping/Notifications/LocalNotificationCenter.swift")

        XCTAssertTrue(notificationSource.contains("func configure()"))
        XCTAssertTrue(appDelegateSource.contains("LocalNotificationCenter.shared.configure()"))
        XCTAssertFalse(appDelegateSource.contains("LocalNotificationCenter.shared.requestAuthorization()"))
    }

    func testScreenRecordingPermissionPassiveCheckDoesNotTriggerScreenCapturePrompt() throws {
        let source = try readSourceFile("Ping/Capture/ScreenCapturePermission.swift")

        XCTAssertTrue(source.contains("CGPreflightScreenCaptureAccess()"))
        XCTAssertFalse(source.contains("SCShareableContent.excludingDesktopWindows"))
        XCTAssertFalse(source.contains("canLoadShareableContent"))
        XCTAssertTrue(source.contains("Do not call ScreenCaptureKit here"))
    }

    func testPermissionRowsUseStableTrailingSlotForButtonsAndGrantedText() throws {
        let source = try readSourceFile("Ping/UI/Setup/PairingView.swift")

        XCTAssertTrue(source.contains("static let permissionTrailingWidth"))
        XCTAssertTrue(source.contains(".frame(width: Layout.permissionTrailingWidth, alignment: .center)"))
        XCTAssertTrue(source.contains(".frame(width: Layout.permissionTrailingWidth)"))
    }

    func testScreenRecordingCopyMentionsMacOSRelaunchRequirement() throws {
        let source = try readSourceFile("Ping/UI/Setup/PairingViewModel.swift")

        XCTAssertTrue(source.contains("Ping을 종료하고 다시 열어야 적용됩니다."))
    }

    func testReleaseBuildUsesStableAdHocDesignatedRequirement() throws {
        let source = try readSourceFile("build-release.sh")

        XCTAssertTrue(source.contains("--requirements '=designated => identifier \"com.youngminpark.ping.Ping\"'"))
    }

    func testReleaseBuildDoesNotOverwriteSparkleHelperEntitlements() throws {
        let source = try readSourceFile("build-release.sh")

        XCTAssertFalse(source.contains("codesign --force --deep --sign - \\\n  --options runtime \\\n  --entitlements Ping.entitlements"))
        XCTAssertTrue(source.contains("--preserve-metadata=entitlements,requirements"))
        XCTAssertTrue(source.contains("sign_preserving_metadata \"$SPARKLE_FRAMEWORK/Versions/B/XPCServices/Installer.xpc\""))
        XCTAssertTrue(source.contains("sign_framework \"$SPARKLE_FRAMEWORK\""))
        XCTAssertTrue(source.contains("--preserve-metadata=entitlements \\\n    \"$code_object\""))
    }

    private func readSourceFile(_ relativePath: String) throws -> String {
        let fileName = URL(fileURLWithPath: relativePath).lastPathComponent
        let fileURL = try XCTUnwrap(Bundle(for: Self.self).resourceURL?.appendingPathComponent(fileName))

        return try String(contentsOf: fileURL, encoding: .utf8)
    }
}
