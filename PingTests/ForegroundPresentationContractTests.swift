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
            from: "private func playMessage(messageId: String, isAutoPlay: Bool = false)",
            to: "private func cancelPlaybackPrefetches"
        )
        // 자동 재생도 앱을 앞으로 가져온다. 로컬 키 감시는 앱이 활성일 때만 이벤트를
        // 받으므로, 포커스를 넘기지 않으면 Esc로 창을 지울 수 없다.
        XCTAssertTrue(playMessage.contains("ForegroundPresenter.activateApp()"))
        XCTAssertTrue(playMessage.contains("window.fadeIn()"))
        XCTAssertFalse(playMessage.contains("if activatesApp {"))

        // 클릭 한 번으로도 지울 수 있어야 한다.
        XCTAssertTrue(playback.contains("ignoresMouseEvents = false"))
        XCTAssertTrue(playback.contains("onDismiss: { [weak self] in"))
        XCTAssertTrue(playback.contains(".onTapGesture { onDismiss() }"))
        XCTAssertFalse(playback.contains(".allowsHitTesting(false)"))

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
