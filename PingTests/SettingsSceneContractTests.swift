import XCTest

final class SettingsSceneContractTests: XCTestCase {
    func testAboutTabDoesNotLinkToMissingGitHubRepository() throws {
        let source = try readSourceFile("Ping/UI/Setup/SettingsScene.swift")
        let aboutSource = try sourceSlice(
            in: source,
            from: "private struct AboutSettingsView",
            to: "private struct SettingsPane"
        )

        XCTAssertFalse(aboutSource.contains("GitHub"))
        XCTAssertFalse(aboutSource.contains("githubURL"))
        XCTAssertFalse(aboutSource.contains("github.com/youngminpark/ping"))
        XCTAssertTrue(aboutSource.contains("licenseDisplayText"))
    }

    func testSettingsMenuUsesDedicatedWindowForMenuBarApp() throws {
        let appDelegateSource = try readSourceFile("Ping/AppDelegate.swift")
        let settingsSource = try readSourceFile("Ping/UI/Setup/SettingsScene.swift")

        XCTAssertTrue(settingsSource.contains("final class SettingsWindow: NSWindow"))
        XCTAssertTrue(appDelegateSource.contains("private var settingsWindow: SettingsWindow?"))
        XCTAssertTrue(appDelegateSource.contains("SettingsWindow(rootView: SettingsView().environmentObject(appState))"))
        XCTAssertFalse(appDelegateSource.contains("showSettingsWindow:"))
    }

    func testSettingsExposeAppearanceModeAndShortcutRecorder() throws {
        let settingsSource = try readSourceFile("Ping/UI/Setup/SettingsScene.swift")
        let hotkeySource = try readSourceFile("Ping/Hotkey/HotkeyManager.swift")
        let preferenceSource = try readSourceFile("Ping/Core/UserPreferences.swift")

        XCTAssertTrue(preferenceSource.contains("enum PingAppearanceMode"))
        XCTAssertTrue(settingsSource.contains("@AppStorage(PingPreferenceKeys.appearanceMode)"))
        XCTAssertTrue(settingsSource.contains("KeyboardShortcuts.Recorder(\"라이트/다크 전환\", name: .appearanceToggle)"))
        XCTAssertTrue(hotkeySource.contains("static let appearanceToggle"))
    }

    func testAboutTabShowsDeveloperCredit() throws {
        let settingsSource = try readSourceFile("Ping/UI/Setup/SettingsScene.swift")
        let aboutSource = try sourceSlice(
            in: settingsSource,
            from: "private struct AboutSettingsView",
            to: "private enum SettingsUserDefaults"
        )

        XCTAssertTrue(aboutSource.contains("개발자 : @0_min._.00"))
    }

    func testStorageTabSeparatesSentReceivedAndRetentionOptions() throws {
        let settingsSource = try readSourceFile("Ping/UI/Setup/SettingsScene.swift")
        let archiveSource = try readSourceFile("Ping/Capture/LocalArchive.swift")

        XCTAssertTrue(settingsSource.contains("LocalArchive.saveSentEnabledKey"))
        XCTAssertTrue(settingsSource.contains("LocalArchive.saveReceivedEnabledKey"))
        XCTAssertTrue(settingsSource.contains("LocalArchive.autoDeleteAfter30DaysKey"))
        XCTAssertTrue(settingsSource.contains("보낸 영상 저장"))
        XCTAssertTrue(settingsSource.contains("받은 영상 저장"))
        XCTAssertTrue(settingsSource.contains("30일 뒤 자동 삭제"))
        XCTAssertTrue(archiveSource.contains("saveSentEnabledKey"))
        XCTAssertTrue(archiveSource.contains("saveReceivedEnabledKey"))
        XCTAssertTrue(archiveSource.contains("autoDeleteAfter30DaysKey"))
        XCTAssertTrue(archiveSource.contains("deleteExpiredFilesIfNeeded"))
    }

    func testRoomSettingsUsesMacOS13CompatibleEmptyState() throws {
        let settingsSource = try readSourceFile("Ping/UI/Setup/SettingsScene.swift")
        let roomSettingsSource = try sourceSlice(
            in: settingsSource,
            from: "private struct RoomSettingsView",
            to: "private struct StorageSettingsView"
        )

        XCTAssertFalse(roomSettingsSource.contains("ContentUnavailableView"))
        XCTAssertTrue(roomSettingsSource.contains("emptyRoomsState"))
    }

    private func readSourceFile(_ relativePath: String) throws -> String {
        let fileName = URL(fileURLWithPath: relativePath).lastPathComponent
        let fileURL = try XCTUnwrap(Bundle(for: Self.self).resourceURL?.appendingPathComponent(fileName))

        return try String(contentsOf: fileURL, encoding: .utf8)
    }

    private func sourceSlice(in source: String, from startMarker: String, to endMarker: String) throws -> String {
        let start = try XCTUnwrap(source.range(of: startMarker)?.lowerBound)
        let end = try XCTUnwrap(source.range(of: endMarker, range: start..<source.endIndex)?.lowerBound)

        return String(source[start..<end])
    }
}
