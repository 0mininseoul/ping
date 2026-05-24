import AppKit
import Sparkle

@MainActor
final class UpdaterController: NSObject, @preconcurrency SPUStandardUserDriverDelegate {
    static let shared = UpdaterController()

    private var controller: SPUStandardUpdaterController!
    private let updateReminderStore: UpdateReminderStore

    var updater: SPUUpdater { controller.updater }

    private override init() {
        updateReminderStore = UpdateReminderStore()
        super.init()
        controller = SPUStandardUpdaterController(
            startingUpdater: false,
            updaterDelegate: nil,
            userDriverDelegate: self
        )
    }

    var supportsGentleScheduledUpdateReminders: Bool {
        true
    }

    func standardUserDriverWillHandleShowingUpdate(
        _ handleShowingUpdate: Bool,
        forUpdate update: SUAppcastItem,
        state: SPUUserUpdateState
    ) {
        NSApp.setActivationPolicy(.regular)

        guard !state.userInitiated else { return }
        NSApp.dockTile.badgeLabel = "1"
        guard updateReminderStore.shouldNotify(version: update.displayVersionString) else { return }

        LocalNotificationCenter.shared.notifyUpdateAvailable(version: update.displayVersionString)
        updateReminderStore.markNotified(version: update.displayVersionString)
    }

    func standardUserDriverDidReceiveUserAttention(forUpdate update: SUAppcastItem) {
        clearUpdateReminder()
    }

    func standardUserDriverWillFinishUpdateSession() {
        clearUpdateReminder()
        NSApp.setActivationPolicy(.accessory)
    }

    func start() {
        controller.startUpdater()
    }

    @objc func checkForUpdates(_ sender: Any?) {
        controller.checkForUpdates(sender)
    }

    private func clearUpdateReminder() {
        NSApp.dockTile.badgeLabel = ""
        LocalNotificationCenter.shared.clearUpdateAvailableNotification()
    }
}
