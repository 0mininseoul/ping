import Foundation
import XCTest
@testable import Ping

final class RemotePushContractTests: XCTestCase {
    func testRegistrarUsesTheMacOSRPCContractAndKeepsTokenInMemory() throws {
        let source = try readRepositoryFile("Ping/Notifications/RemotePushRegistrar.swift")

        XCTAssertTrue(source.contains("@MainActor"))
        XCTAssertTrue(source.contains("NSApplication.shared.registerForRemoteNotifications()"))
        XCTAssertTrue(source.contains("\"token_text\""))
        XCTAssertTrue(source.contains("\"platform_text\": \"macos\""))
        XCTAssertTrue(source.contains("\"environment_text\""))
        XCTAssertTrue(source.contains("\"sound_preference_text\""))
        XCTAssertTrue(source.contains("#if DEBUG"))
        XCTAssertTrue(source.contains("\"sandbox\""))
        XCTAssertTrue(source.contains("\"production\""))
        XCTAssertTrue(source.contains("String(format: \"%02x\", byte)"))
        XCTAssertFalse(source.contains("UserDefaults"))
        XCTAssertFalse(source.contains("Keychain"))
        XCTAssertFalse(source.contains("SecItem"))
    }

    func testAppDelegateForwardsRemoteRegistrationCallbacksAndRetriesWithLifecycle() throws {
        let source = try readRepositoryFile("Ping/AppDelegate.swift")

        XCTAssertTrue(source.contains("didRegisterForRemoteNotificationsWithDeviceToken"))
        XCTAssertTrue(source.contains("didFailToRegisterForRemoteNotificationsWithError"))
        XCTAssertTrue(source.contains("RemotePushRegistrar.shared.update(deviceToken: deviceToken)"))
        XCTAssertTrue(source.contains("RemotePushRegistrar.shared.recordRegistrationFailure(error)"))
        XCTAssertTrue(source.contains("await RemotePushRegistrar.shared.registerIfPossible(uid: uid)"))
        let settings = try readRepositoryFile("Ping/UI/Setup/SettingsScene.swift")
        XCTAssertTrue(settings.contains("await RemotePushRegistrar.shared.refreshSoundPreference(uid: uid)"))
    }

    func testAccountChangeWaitsForStaleRemoteRegistrationBeforeBootstrappingNewAccount() throws {
        let registrar = try readRepositoryFile("Ping/Notifications/RemotePushRegistrar.swift")
        XCTAssertTrue(registrar.contains("registrationGeneration"))
        XCTAssertTrue(registrar.contains("invalidatePendingRegistration"))
        XCTAssertTrue(registrar.contains("await task.value"))
        XCTAssertTrue(registrar.contains("guard self.registrationGeneration == generation"))
        XCTAssertTrue(registrar.contains("token = encoded"))

        let appDelegate = try readRepositoryFile("Ping/AppDelegate.swift")
        XCTAssertTrue(appDelegate.contains("await self.teardownForAccountChange()"))
        XCTAssertTrue(appDelegate.contains("await teardownForAccountChange()"))
        let teardown = try XCTUnwrap(appDelegate.range(of: "await self.teardownForAccountChange()"))
        let bootstrap = try XCTUnwrap(appDelegate.range(of: "await bootstrapBackend()"))
        XCTAssertLessThan(teardown.lowerBound, bootstrap.lowerBound)
    }

    func testNotificationCenterNormalizesRemoteAndLocalIdentifiersThroughOneParser() throws {
        let source = try readRepositoryFile("Ping/Notifications/LocalNotificationCenter.swift")

        XCTAssertTrue(source.contains("enum NotificationPayload"))
        XCTAssertTrue(source.contains("static func parse(userInfo"))
        XCTAssertTrue(source.contains("messageId"))
        XCTAssertTrue(source.contains("message_id"))
        XCTAssertTrue(source.contains("inviteId"))
        XCTAssertTrue(source.contains("invite_id"))
        XCTAssertTrue(source.contains("room_id"))
        XCTAssertTrue(source.contains("roomId"))
        XCTAssertTrue(source.contains("chat_id"))
        XCTAssertTrue(source.contains("chatId"))
        XCTAssertTrue(source.contains("NotificationPayload.parse(userInfo: info)"))
    }

    func testPayloadParserAcceptsRemoteAndLegacyIdentifierSpellings() {
        XCTAssertEqual(
            NotificationPayload.parse(userInfo: [
                "message_id": "remote-message",
                "roomId": "remote-room"
            ]),
            .message(messageId: "remote-message", roomId: "remote-room")
        )
        XCTAssertEqual(
            NotificationPayload.parse(userInfo: [
                "inviteId": "legacy-invite",
                "room_id": "legacy-room"
            ]),
            .invitation(inviteId: "legacy-invite", roomId: "legacy-room")
        )
        XCTAssertEqual(
            NotificationPayload.parse(userInfo: [
                "type": "chat",
                "chatId": "remote-chat",
                "room_id": "chat-room"
            ]),
            .chat(chatId: "remote-chat", roomId: "chat-room")
        )
        XCTAssertEqual(
            NotificationPayload.parse(userInfo: [
                "type": "chat",
                "chat_id": "",
                "roomId": "catch-up-room"
            ]),
            .chat(chatId: nil, roomId: "catch-up-room")
        )
    }

    func testExistingNotificationActionsAndForegroundPresentationRemainIntact() throws {
        let source = try readRepositoryFile("Ping/Notifications/LocalNotificationCenter.swift")

        XCTAssertTrue(source.contains("case incomingMessage = \"ping.message\""))
        XCTAssertTrue(source.contains("case incomingInvitation = \"ping.invitation\""))
        XCTAssertTrue(source.contains("case availableUpdate = \"ping.update\""))
        XCTAssertTrue(source.contains("onAcceptInvitation?"))
        XCTAssertTrue(source.contains("onRejectInvitation?"))
        XCTAssertTrue(source.contains("onViewChatMessage?"))
        XCTAssertTrue(source.contains("onViewMessage?"))
        XCTAssertTrue(source.contains("onCheckForUpdates?"))
        XCTAssertTrue(source.contains("completionHandler([.banner, .sound])"))
    }

    func testMacOSAPNsEntitlementsUseEnvironmentSpecificValuesWithoutChangingDeployment() throws {
        let release = try readPlist("Ping.entitlements")
        let debug = try readPlist("PingDebug.entitlements")
        let project = try readRepositoryFile("project.yml")

        XCTAssertEqual(release["com.apple.developer.aps-environment"] as? String, "production")
        XCTAssertEqual(debug["com.apple.developer.aps-environment"] as? String, "development")
        XCTAssertTrue(project.contains("macOS: \"13.0\""))
        XCTAssertTrue(project.contains("SWIFT_VERSION: \"6.0\""))
        XCTAssertTrue(project.contains("com.youngminpark.ping.Ping"))
    }

    private func readRepositoryFile(_ relativePath: String) throws -> String {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        return try String(contentsOf: root.appendingPathComponent(relativePath), encoding: .utf8)
    }

    private func readPlist(_ relativePath: String) throws -> [String: Any] {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let data = try Data(contentsOf: root.appendingPathComponent(relativePath))
        let plist = try PropertyListSerialization.propertyList(from: data, format: nil)
        return try XCTUnwrap(plist as? [String: Any])
    }
}
