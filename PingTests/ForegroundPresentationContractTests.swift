import XCTest

final class ForegroundPresentationContractTests: XCTestCase {
    func testUserFacingWindowsUseAccessorySafeForegroundPresenter() throws {
        let presenter = try readProjectSource("Ping/Core/ForegroundPresenter.swift")
        let appDelegate = try readProjectSource("Ping/AppDelegate.swift")

        XCTAssertTrue(presenter.contains("enum ForegroundPresenter"))
        XCTAssertTrue(presenter.contains("NSRunningApplication.current.activate(options: [.activateAllWindows, .activateIgnoringOtherApps])"))
        XCTAssertTrue(presenter.contains("window.orderFrontRegardless()"))
        XCTAssertTrue(presenter.contains("window.makeKeyAndOrderFront(nil)"))

        let roomManager = try sourceSlice(
            in: appDelegate,
            from: "private func presentRoomManager(",
            to: "@objc private func showSettings()"
        )
        XCTAssertTrue(roomManager.contains("ForegroundPresenter.present(roomManagerWindow)"))

        let settings = try sourceSlice(
            in: appDelegate,
            from: "@objc private func showSettings()",
            to: "private func handleInvite"
        )
        XCTAssertTrue(settings.contains("ForegroundPresenter.present(settingsWindow)"))
    }

    func testNotificationClickPlaybackAndChatFocusForceForegroundOrdering() throws {
        let appDelegate = try readProjectSource("Ping/AppDelegate.swift")
        let playback = try readProjectSource("Ping/UI/Playback/PlaybackWindow.swift")

        let playMessage = try sourceSlice(
            in: appDelegate,
            from: "private func playMessage(messageId: String)",
            to: "private func cachedVideoURL"
        )
        XCTAssertTrue(playMessage.contains("ForegroundPresenter.activateApp()"))

        XCTAssertTrue(playback.contains("ForegroundPresenter.present(self)"))
        XCTAssertTrue(playback.contains("ForegroundPresenter.present(expanded)"))
        XCTAssertTrue(playback.contains("ForegroundPresenter.present(self)"))
    }

    func testSparkleUpdateChecksActivateBeforeShowingUserDriverUI() throws {
        let updater = try readProjectSource("Ping/Updater/UpdaterController.swift")

        let checkForUpdates = try sourceSlice(
            in: updater,
            from: "@objc func checkForUpdates",
            to: "private func clearUpdateReminder"
        )
        XCTAssertTrue(checkForUpdates.contains("ForegroundPresenter.activateApp()"))
        XCTAssertTrue(checkForUpdates.contains("controller.checkForUpdates(sender)"))

        let willShow = try sourceSlice(
            in: updater,
            from: "func standardUserDriverWillHandleShowingUpdate",
            to: "func standardUserDriverDidReceiveUserAttention"
        )
        XCTAssertTrue(willShow.contains("if state.userInitiated"))
        XCTAssertTrue(willShow.contains("ForegroundPresenter.activateApp()"))
    }

    private func readProjectSource(_ relativePath: String) throws -> String {
        let projectRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()

        return try String(
            contentsOf: projectRoot.appendingPathComponent(relativePath),
            encoding: .utf8
        )
    }

    private func sourceSlice(in source: String, from startMarker: String, to endMarker: String) throws -> String {
        let start = try XCTUnwrap(source.range(of: startMarker)?.lowerBound)
        let end = try XCTUnwrap(source.range(of: endMarker, range: start..<source.endIndex)?.lowerBound)
        return String(source[start..<end])
    }
}
