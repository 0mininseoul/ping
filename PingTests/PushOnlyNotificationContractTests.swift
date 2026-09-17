import XCTest

final class PushOnlyNotificationContractTests: XCTestCase {
    func testUserEventsHaveNoLocalNotificationSchedulingPath() throws {
        let appDelegate = try readRepositoryFile("Ping/AppDelegate.swift")
        let notifications = try readRepositoryFile("Ping/Notifications/LocalNotificationCenter.swift")

        for helper in [
            "notifyIncomingMessage",
            "notifyIncomingChat",
            "notifyChatCatchUp",
            "notifyIncomingInvitation"
        ] {
            XCTAssertFalse(appDelegate.contains(helper), "AppDelegate still references \(helper)")
            XCTAssertFalse(notifications.contains(helper), "LocalNotificationCenter still defines \(helper)")
        }

        let updateRange = try XCTUnwrap(notifications.range(of: "func notifyUpdateAvailable"))
        let eventSchedulingSource = String(notifications[..<updateRange.lowerBound])
        XCTAssertFalse(eventSchedulingSource.contains("UNNotificationRequest"))
        XCTAssertFalse(eventSchedulingSource.contains(".add("))
    }

    func testSparkleUpdateRemindersRemainLocal() throws {
        let source = try readRepositoryFile("Ping/Notifications/LocalNotificationCenter.swift")
        let update = try sourceSlice(
            in: source,
            from: "func notifyUpdateAvailable",
            to: "func clearUpdateAvailableNotification"
        )

        XCTAssertTrue(update.contains("UNNotificationRequest"))
        XCTAssertTrue(update.contains("UNUserNotificationCenter.current().add(request"))
        XCTAssertTrue(update.contains("updateAvailableIdentifier"))
    }

    func testInvitationObserverOnlyRefreshesPendingInvitationState() throws {
        let source = try readRepositoryFile("Ping/AppDelegate.swift")
        let observer = try sourceSlice(
            in: source,
            from: "invitationObserverTask = Task",
            to: "incomingMessageTask = Task"
        )

        XCTAssertTrue(observer.contains("appState.pendingInvitations = invitations"))
        XCTAssertFalse(observer.contains("LocalNotificationCenter"))
        XCTAssertFalse(observer.contains("UNUserNotificationCenter"))
    }

    func testChatRealtimeObserverLeavesRefreshToHistoryViewsWithoutLocalBanners() throws {
        let source = try readRepositoryFile("Ping/AppDelegate.swift")
        let handler = try sourceSlice(
            in: source,
            from: "private func handleChatRealtimeEvent",
            to: "private func shouldNotify"
        )

        XCTAssertTrue(handler.contains("fetchIncomingVideosNow()"))
        XCTAssertFalse(handler.contains("notifyIncomingChat"))
        XCTAssertFalse(handler.contains("notifyChatCatchUp"))
        XCTAssertFalse(handler.contains("UNUserNotificationCenter"))
    }

    func testVideoObserverStartsAutoReplyBeforeMarkingNotifiedAndKeepsPlaybackPreparation() throws {
        let source = try readRepositoryFile("Ping/AppDelegate.swift")
        let delivery = try sourceSlice(
            in: source,
            from: "private func deliverIncomingVideo",
            to: "private func fetchIncomingVideosNow"
        )

        let autoReply = try XCTUnwrap(delivery.range(of: "autoFaceReply.handleIncoming"))
        let markNotified = try XCTUnwrap(delivery.range(of: "messageService.markNotified"))
        XCTAssertLessThan(autoReply.lowerBound, markNotified.lowerBound)
        XCTAssertTrue(delivery.contains("ledger.remember(.video"))
        XCTAssertTrue(delivery.contains("PingAutoPlayPreference.shouldAutoPlay"))
        XCTAssertTrue(delivery.contains("playbackVideoCache.prefetch"))
        XCTAssertFalse(delivery.contains("notifyIncomingMessage"))
    }

    func testColdStartVideoRowsAreGatedOutBeforeAutoReplyCoordinator() throws {
        let source = try readRepositoryFile("Ping/AppDelegate.swift")
        let delivery = try sourceSlice(
            in: source,
            from: "private func deliverIncomingVideo",
            to: "private func fetchIncomingVideosNow"
        )

        let gate = try XCTUnwrap(delivery.range(of: "isLiveVideoArrival(message)"))
        let autoReply = try XCTUnwrap(delivery.range(of: "autoFaceReply.handleIncoming"))
        XCTAssertLessThan(gate.lowerBound, autoReply.lowerBound)
        XCTAssertTrue(source.contains("return createdAt > appStartTime"))
    }

    func testRemoteResponsePlaybackCannotStartAnAutomaticFaceReply() throws {
        let center = try readRepositoryFile("Ping/Notifications/LocalNotificationCenter.swift")
        let appDelegate = try readRepositoryFile("Ping/AppDelegate.swift")
        let response = try sourceSlice(
            in: center,
            from: "nonisolated func userNotificationCenter(",
            to: "nonisolated func userNotificationCenter(\n        _ center: UNUserNotificationCenter,\n        willPresent"
        )
        let playback = try sourceSlice(
            in: appDelegate,
            from: "private func playMessage(messageId: String",
            to: "private func cancelPlaybackPrefetches"
        )

        XCTAssertTrue(response.contains("onViewMessage?(messageId)"))
        XCTAssertFalse(response.contains("autoFaceReply"))
        XCTAssertFalse(playback.contains("autoFaceReply"))
    }

    func testAppStartTimeStillFeedsAutoReplyAndAutoplayFreshnessChecks() throws {
        let source = try readRepositoryFile("Ping/AppDelegate.swift")

        XCTAssertTrue(source.contains("private let appStartTime = Date()"))
        XCTAssertTrue(source.contains("appStartedAt: appStartTime"))
        XCTAssertTrue(source.contains("PingAutoPlayPreference.shouldAutoPlay"))
    }

    private func readRepositoryFile(_ relativePath: String) throws -> String {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        return try String(contentsOf: root.appendingPathComponent(relativePath), encoding: .utf8)
    }

    private func sourceSlice(in source: String, from startMarker: String, to endMarker: String) throws -> String {
        let start = try XCTUnwrap(source.range(of: startMarker)?.lowerBound)
        let end = try XCTUnwrap(source.range(of: endMarker, range: start..<source.endIndex)?.lowerBound)
        return String(source[start..<end])
    }
}
