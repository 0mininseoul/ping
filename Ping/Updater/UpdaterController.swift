import AppKit
import Sparkle

@MainActor
final class UpdaterController: NSObject, @preconcurrency SPUStandardUserDriverDelegate {
    static let shared = UpdaterController()

    private let appcastURL = URL(string: "https://ping0min.vercel.app/appcast.xml")!
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
        guard AppInstallLocation.canUseSparkleUpdates() else { return }
        controller.startUpdater()
    }

    @objc func checkForUpdates(_ sender: Any?) {
        guard AppInstallLocation.canUseSparkleUpdates() else {
            Task { @MainActor in
                await showManualDownloadUpdateOffer()
            }
            return
        }

        controller.checkForUpdates(sender)
    }

    private func clearUpdateReminder() {
        NSApp.dockTile.badgeLabel = ""
        LocalNotificationCenter.shared.clearUpdateAvailableNotification()
    }

    private func showManualDownloadUpdateOffer() async {
        let offer = await latestManualUpdateOffer()
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)

        let alert = NSAlert()
        alert.alertStyle = .informational

        if let offer {
            alert.messageText = "Ping \(offer.displayVersion) 업데이트를 설치할 수 있습니다."
            alert.informativeText = "현재 Ping이 다운로드된 위치에서 실행 중이라 자동 업데이트를 적용할 수 없습니다. 최신 버전을 내려받아 Ping.app을 응용 프로그램 폴더로 옮긴 뒤 다시 실행해 주세요."
            alert.addButton(withTitle: "최신 버전 다운로드")
            alert.addButton(withTitle: "나중에")

            if alert.runModal() == .alertFirstButtonReturn {
                NSWorkspace.shared.open(offer.downloadURL)
            }
        } else {
            alert.messageText = "Ping을 응용 프로그램 폴더로 옮겨 주세요."
            alert.informativeText = "다운로드된 위치나 디스크 이미지에서 실행 중인 Ping은 Sparkle 자동 업데이트를 적용할 수 없습니다. Ping.app을 응용 프로그램 폴더로 옮긴 뒤 다시 실행하면 업데이트 확인이 정상 동작합니다."
            alert.addButton(withTitle: "다운로드 페이지 열기")
            alert.addButton(withTitle: "나중에")

            if alert.runModal() == .alertFirstButtonReturn,
               let downloadPage = URL(string: "https://ping0min.vercel.app") {
                NSWorkspace.shared.open(downloadPage)
            }
        }

        NSApp.setActivationPolicy(.accessory)
    }

    private func latestManualUpdateOffer() async -> AppcastUpdateOffer? {
        do {
            let (data, response) = try await URLSession.shared.data(from: appcastURL)
            guard let httpResponse = response as? HTTPURLResponse,
                  (200..<300).contains(httpResponse.statusCode) else {
                return nil
            }

            let currentBuild = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? ""
            return AppcastUpdateOfferParser.latestOffer(in: data, currentBuild: currentBuild)
        } catch {
            return nil
        }
    }
}
