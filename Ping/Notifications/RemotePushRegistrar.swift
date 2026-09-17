import AppKit
import Foundation
import UserNotifications

/// Owns the APNs token for this running process and registers it for the
/// currently active anonymous account. The token is deliberately not persisted:
/// APNs delivers a fresh token through the application delegate when the app
/// launches or its registration changes.
@MainActor
final class RemotePushRegistrar {
    static let shared = RemotePushRegistrar()

    private(set) var token: String?
    private(set) var lastRegistrationError: Error?

    private var lastSuccessfulRegistration: RegistrationKey?
    private var registrationTask: Task<Void, Never>?

    private init() {}

    /// APNs uses the development topic for Debug and the production topic for
    /// release builds. Keep this compile-time so a release cannot accidentally
    /// register a production binary against the sandbox endpoint.
    var apnsEnvironment: String {
        #if DEBUG
        return "sandbox"
        #else
        return "production"
        #endif
    }

    /// Register with APNs only after the user has made an authorization
    /// decision. This check is used on launch and network recovery so it never
    /// consumes the onboarding permission prompt.
    func registerForRemoteNotificationsIfAuthorized() async {
        let settings = await UNUserNotificationCenter.current().notificationSettings()
        guard Self.canRegister(for: settings.authorizationStatus) else { return }
        registerForRemoteNotifications()
    }

    /// Called by `LocalNotificationCenter` after notification authorization,
    /// and by launch/recovery paths once authorization is already known.
    func registerForRemoteNotifications() {
        NSApplication.shared.registerForRemoteNotifications()
    }

    /// Receives the raw callback token from AppKit. Keep only its lowercase
    /// hexadecimal representation in memory for this process.
    func update(deviceToken: Data) {
        let encoded = Self.hexToken(deviceToken)
        guard !encoded.isEmpty else { return }

        token = encoded
        lastSuccessfulRegistration = nil
        lastRegistrationError = nil

        guard let uid = SupabaseClient.shared.activeUserId else { return }
        scheduleRegistration(for: uid)
    }

    /// Register the current process token for an active account. Calls are
    /// idempotent on the backend; the local key only suppresses duplicate
    /// requests during launch/account setup. A failed request leaves the key
    /// unset so network recovery can retry it.
    func registerIfPossible(uid: String) async {
        guard !uid.isEmpty, let token, !token.isEmpty else { return }
        guard SupabaseClient.shared.activeUserId == uid else {
            NSLog("APNs token registration skipped for inactive account")
            return
        }

        let soundPreference = PingNotificationSound.current.rawValue
        let key = RegistrationKey(
            uid: uid,
            token: token,
            environment: apnsEnvironment,
            soundPreference: soundPreference
        )
        if lastSuccessfulRegistration == key { return }

        do {
            try await SupabaseClient.shared.rpcVoid("ping_register_device_token", body: [
                "p_token": token,
                "p_platform": "macos",
                "p_environment": apnsEnvironment,
                "p_sound_preference": soundPreference
            ])
            guard SupabaseClient.shared.activeUserId == uid else { return }
            lastSuccessfulRegistration = key
            lastRegistrationError = nil
        } catch {
            lastRegistrationError = error
            NSLog("APNs token registration failed for " + String(describing: error))
        }
    }

    /// Force a re-registration after the local sound preference changes. The
    /// raw token remains in memory and the backend receives the new preference.
    func refreshSoundPreference(uid: String) async {
        lastSuccessfulRegistration = nil
        await registerIfPossible(uid: uid)
    }

    /// Registration failures are intentionally non-fatal. The next launch,
    /// bootstrap, account switch, or satisfied network path retries it.
    func recordRegistrationFailure(_ error: Error) {
        lastRegistrationError = error
        NSLog("APNs remote registration failed: " + String(describing: error))
    }

    private func scheduleRegistration(for uid: String) {
        registrationTask?.cancel()
        registrationTask = Task { @MainActor [weak self] in
            await self?.registerIfPossible(uid: uid)
        }
    }

    private static func hexToken(_ data: Data) -> String {
        data.map { byte in String(format: "%02x", byte) }.joined()
    }

    private static func canRegister(for status: UNAuthorizationStatus) -> Bool {
        switch status {
        case .authorized, .provisional, .ephemeral:
            return true
        case .denied, .notDetermined:
            return false
        @unknown default:
            return false
        }
    }

    private struct RegistrationKey: Equatable {
        let uid: String
        let token: String
        let environment: String
        let soundPreference: String
    }
}
