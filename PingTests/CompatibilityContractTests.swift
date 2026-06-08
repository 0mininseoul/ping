import XCTest

final class CompatibilityContractTests: XCTestCase {
    func testProjectTargetsMacOS13AndSwift6() throws {
        let project = try readFixture("project.yml")
        let info = try readFixture("Ping/Info.plist")
        let appTarget = try sourceSlice(in: project, from: "  Ping:", to: "  PingTests:")
        let testTarget = try sourceSlice(in: project, from: "  PingTests:")

        XCTAssertTrue(project.contains("macOS: \"13.0\""))
        XCTAssertTrue(project.contains("MACOSX_DEPLOYMENT_TARGET: \"13.0\""))
        XCTAssertTrue(project.contains("SWIFT_VERSION: \"6.0\""))
        XCTAssertTrue(appTarget.contains("deploymentTarget: \"13.0\""))
        XCTAssertTrue(testTarget.contains("deploymentTarget: \"13.0\""))
        XCTAssertTrue(info.contains("<key>LSMinimumSystemVersion</key>"))
        XCTAssertTrue(info.contains("<string>13.0</string>"))
    }

    func testMacAppIsLaunchServicesSearchableWhileHidingDockAtRuntime() throws {
        let project = try readFixture("project.yml")
        let info = try readFixture("Ping/Info.plist")
        let appDelegate = try readFixture("AppDelegate.swift")
        let appTarget = try sourceSlice(in: project, from: "  Ping:", to: "  PingTests:")
        let willFinish = try sourceSlice(
            in: appDelegate,
            from: "func applicationWillFinishLaunching",
            to: "func applicationDidFinishLaunching"
        )
        let didFinish = try sourceSlice(
            in: appDelegate,
            from: "func applicationDidFinishLaunching",
            to: "func applicationWillTerminate"
        )

        XCTAssertFalse(appTarget.contains("LSUIElement: true"))
        XCTAssertFalse(info.contains("<key>LSUIElement</key>"))
        XCTAssertTrue(appTarget.contains("LSApplicationCategoryType: public.app-category.social-networking"))
        XCTAssertTrue(info.contains("<key>LSApplicationCategoryType</key>"))
        XCTAssertTrue(info.contains("<string>public.app-category.social-networking</string>"))
        XCTAssertTrue(willFinish.contains("enforceAccessoryActivationPolicy()"))
        XCTAssertTrue(didFinish.contains("enforceAccessoryActivationPolicySoon()"))
        XCTAssertTrue(appDelegate.contains("func applicationDidBecomeActive"))
        XCTAssertTrue(appDelegate.contains("func applicationShouldHandleReopen"))
        XCTAssertTrue(appDelegate.contains("NSApp.setActivationPolicy(.accessory)"))
    }

    func testDocsDescribeMacOS13CompatibilityInsteadOfMacOS26Only() throws {
        let spec = try readFixture("PING_PROJECT_SPECIFICATION.md")
        let readme = try readFixture("README.md")
        let agents = try readFixture("AGENTS.md")

        for document in [spec, readme, agents] {
            XCTAssertTrue(document.contains("macOS 13 Ventura 이상"))
            XCTAssertFalse(document.contains("macOS 26 Tahoe 전용"))
            XCTAssertFalse(document.contains("macOS 26 Tahoe 이상"))
            XCTAssertFalse(document.contains("macOS 26을 최저"))
            XCTAssertFalse(document.contains("`macOS: \"26.0\"`"))
            XCTAssertFalse(document.contains("`macOS 14` / `15` 로 deploymentTarget 낮추지 말 것"))
        }
    }

    func testAppSwiftSourcesUseGlassEffectOnlyThroughCompatibilityWrapper() throws {
        let allowedFixtureName = "GlassEffectCompat.swift"
        let appSourceFixtureNames = [
            "GlassEffectCompat.swift",
            "GlassChip.swift",
            "MirrorView.swift",
            "PartnerPicker.swift",
            "GlassButton.swift",
            "GlassPanel.swift",
            "PairingView.swift",
            "RoomListView.swift",
            "RoomSearchView.swift",
            "SettingsScene.swift",
            "PingDesign.swift",
            "CameraManager.swift",
            "PairingViewModel.swift",
            "RoomManagerWindow.swift",
            "HotkeyManager.swift",
            "UserPreferences.swift",
            "InviteLink.swift",
            "AppState.swift",
            "RoomLimits.swift",
            "PingError.swift",
            "LocalArchive.swift",
            "VideoRecorder.swift",
            "VideoCropper.swift",
            "AppDelegate.swift",
            "InvitationService.swift",
            "MessageService.swift",
            "SupabaseClient.swift",
        ]

        let directGlassEffectFixtures = try appSourceFixtureNames.compactMap { fixtureName -> String? in
            let contents = try readFixture(fixtureName)
            return contents.contains(".glassEffect(") ? fixtureName : nil
        }

        XCTAssertEqual(
            directGlassEffectFixtures,
            [allowedFixtureName],
            "Direct .glassEffect() is only allowed in \(allowedFixtureName). Found in: \(directGlassEffectFixtures.joined(separator: ", "))"
        )
    }

    private func readFixture(_ relativePath: String) throws -> String {
        let fileName = URL(fileURLWithPath: relativePath).lastPathComponent
        let fileURL = try XCTUnwrap(Bundle(for: Self.self).resourceURL?.appendingPathComponent(fileName))

        return try String(contentsOf: fileURL, encoding: .utf8)
    }

    private func sourceSlice(in source: String, from startMarker: String, to endMarker: String? = nil) throws -> String {
        let start = try XCTUnwrap(source.range(of: startMarker)?.lowerBound)

        guard let endMarker else {
            return String(source[start...])
        }

        let end = try XCTUnwrap(source.range(of: endMarker, range: start..<source.endIndex)?.lowerBound)
        return String(source[start..<end])
    }
}
