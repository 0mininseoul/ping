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
        XCTAssertTrue(docs.contains("build 40 이상부터 자동 업데이트 설치 경로가 정상화"))
    }

    func testBackgroundSparkleUpdatesUseGentleReminderNotification() throws {
        let updater = try readSourceFile("UpdaterController.swift")
        let notifications = try readSourceFile("LocalNotificationCenter.swift")
        let appDelegate = try readSourceFile("AppDelegate.swift")

        XCTAssertTrue(updater.contains("SPUStandardUserDriverDelegate"))
        XCTAssertTrue(updater.contains("userDriverDelegate: self"))
        XCTAssertTrue(updater.contains("supportsGentleScheduledUpdateReminders"))
        XCTAssertTrue(updater.contains("notifyUpdateAvailable(version: update.displayVersionString)"))
        XCTAssertTrue(updater.contains("standardUserDriverDidReceiveUserAttention"))
        XCTAssertTrue(updater.contains("controller.checkForUpdates(sender)"))

        XCTAssertTrue(notifications.contains("case availableUpdate = \"ping.update\""))
        XCTAssertTrue(notifications.contains("case viewUpdate = \"ping.update.view\""))
        XCTAssertTrue(notifications.contains("func notifyUpdateAvailable(version: String)"))
        XCTAssertTrue(notifications.contains("onCheckForUpdates?()"))
        XCTAssertTrue(appDelegate.contains("LocalNotificationCenter.shared.onCheckForUpdates"))
    }

    func testScheduledUpdateNotificationIsOnePerLatestVersion() throws {
        let updater = try readSourceFile("UpdaterController.swift")
        let notifications = try readSourceFile("LocalNotificationCenter.swift")

        XCTAssertTrue(updater.contains("UpdateReminderStore"))
        XCTAssertTrue(updater.contains("shouldNotify(version: update.displayVersionString)"))
        XCTAssertTrue(updater.contains("markNotified(version: update.displayVersionString)"))
        XCTAssertTrue(notifications.contains("static let updateAvailableIdentifier = \"ping.update.available\""))
        XCTAssertTrue(notifications.contains("removePendingNotificationRequests(withIdentifiers: [Self.updateAvailableIdentifier])"))
        XCTAssertTrue(notifications.contains("removeDeliveredNotifications(withIdentifiers: [Self.updateAvailableIdentifier])"))
        XCTAssertTrue(notifications.contains("\"version\": version"))
    }

    func testUpdatePromptsDoNotPromoteMenuBarAppToDockApp() throws {
        let updater = try readSourceFile("UpdaterController.swift")

        XCTAssertFalse(updater.contains("NSApp.setActivationPolicy(.regular)"))
        XCTAssertFalse(updater.contains("NSApp.dockTile.badgeLabel"))
        XCTAssertTrue(updater.contains("NSApp.setActivationPolicy(.accessory)"))
    }

    private func readSourceFile(_ relativePath: String) throws -> String {
        let fileName = URL(fileURLWithPath: relativePath).lastPathComponent
        let fileURL = try XCTUnwrap(Bundle(for: Self.self).resourceURL?.appendingPathComponent(fileName))

        return try String(contentsOf: fileURL, encoding: .utf8)
    }
}
