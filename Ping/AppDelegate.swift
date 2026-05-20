import AppKit
import SwiftUI

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem?
    private var mirrorWindow: MirrorWindow?
    private var onboardingWindow: OnboardingWindow?
    private var roomManagerWindow: RoomManagerWindow?
    private var settingsWindow: SettingsWindow?
    private var playbackWindows: [PlaybackWindow] = []
    private var playbackCache: [String: URL] = [:]
    private var playbackPrefetchTasks: [String: Task<URL, Error>] = [:]

    private let appState = AppState.shared
    private let camera = CameraManager()
    private let screenCapture = ScreenCaptureManager()
    private let mirrorViewModel = MirrorViewModel()
    private let messageService = MessageService()
    private let userService = UserService()
    private let roomService = RoomService()
    private let invitationService = InvitationService()
    private let storageService = StorageService()
    private let cleanupService = CleanupService()
    private let appStartTime = Date()
    private let notifiedMessageIdsKey = "ping.notifications.notifiedMessageIds"

    private var roomObserverTask: Task<Void, Never>?
    private var invitationObserverTask: Task<Void, Never>?
    private var incomingMessageTask: Task<Void, Never>?
    private var bootstrapTask: Task<Void, Never>?
    private var cameraStartTask: Task<Void, Never>?
    private var pendingInviteToken: String?
    private var currentMirrorMode: CaptureMode?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        PingAppearanceMode.applyCurrent()
        LocalArchive.migrateLegacyPreferencesIfNeeded()
        LocalArchive.ensureFolders()
        setupStatusBar()
        setupNotifications()
        setupHotkey()

        if !ProcessInfo.processInfo.isRunningUnitTests {
            UpdaterController.shared.start()
            startBootstrapTaskIfNeeded()
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        bootstrapTask?.cancel()
        roomObserverTask?.cancel()
        invitationObserverTask?.cancel()
        incomingMessageTask?.cancel()
        cameraStartTask?.cancel()
        camera.stop()
    }

    func application(_ application: NSApplication, open urls: [URL]) {
        guard let token = urls.compactMap(PingInviteLink.token(from:)).first else {
            return
        }

        acceptInviteLink(token: token)
    }

    private func setupStatusBar() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        let menuIcon = NSImage(named: "MenuBarIcon")
            ?? NSImage(systemSymbolName: "circle.dotted.circle", accessibilityDescription: "Ping")
        menuIcon?.isTemplate = false
        menuIcon?.size = NSSize(width: 18, height: 18)
        item.button?.image = menuIcon
        item.button?.imageScaling = .scaleProportionallyDown

        item.menu = StatusMenuBuilder.makeMenu(target: self)
        statusItem = item
    }

    private func setupNotifications() {
        Task {
            _ = await LocalNotificationCenter.shared.requestAuthorization()
        }

        LocalNotificationCenter.shared.onViewMessage = { [weak self] messageId in
            self?.playMessage(messageId: messageId)
        }
        LocalNotificationCenter.shared.onOpenInvitations = { [weak self] in
            self?.showRoomManager()
        }
        LocalNotificationCenter.shared.onAcceptInvitation = { [weak self] inviteId in
            self?.acceptInvitation(inviteId: inviteId)
        }
        LocalNotificationCenter.shared.onRejectInvitation = { [weak self] inviteId in
            self?.rejectInvitation(inviteId: inviteId)
        }
    }

    private func setupHotkey() {
        HotkeyManager.shared.register(
            onCaptureFace: { [weak self] in self?.toggleMirror(mode: .faceOnly) },
            onAppearanceToggle: { [weak self] in self?.toggleAppearanceMode() },
            onCaptureScreenFace: { [weak self] in self?.toggleMirror(mode: .screenFace) }
        )
    }

    private func startBootstrapTaskIfNeeded() {
        guard bootstrapTask == nil else { return }

        bootstrapTask = Task { @MainActor [weak self] in
            guard let self else { return }
            await self.bootstrapBackend()
            self.bootstrapTask = nil
        }
    }

    private func bootstrapBackend() async {
        do {
            let uid = try await SupabaseClient.shared.bootstrap()
            let existing = try await userService.get(uid: uid)

            if let existing {
                try await userService.upsert(uid: uid, nickname: existing.nickname)
                appState.currentUser = try await userService.get(uid: uid) ?? existing
                startObservers(uid: uid, opensRoomManagerWhenEmpty: !roomSetupWasDeferred)
                runCleanup(uid: uid)
                consumePendingInviteTokenIfAvailable()
            } else {
                showOnboarding(uid: uid)
            }
        } catch {
            appState.backendStatusMessage = error.localizedDescription
            NSLog("Backend bootstrap failed: \(error)")
            showSetupError(error)
        }
    }

    private func consumePendingInviteTokenIfAvailable() {
        guard let token = pendingInviteToken else { return }

        pendingInviteToken = nil
        acceptInviteLink(token: token)
    }

    private func startObservers(uid: String, opensRoomManagerWhenEmpty: Bool = true) {
        roomObserverTask?.cancel()
        invitationObserverTask?.cancel()
        incomingMessageTask?.cancel()

        roomObserverTask = Task { @MainActor in
            var didHandleInitialSnapshot = false

            for await rooms in roomService.observeMyRooms(uid: uid) {
                appState.rooms = rooms
                if !rooms.isEmpty {
                    UserDefaults.standard.set(false, forKey: PingPreferenceKeys.roomSetupDeferred)
                }

                if !didHandleInitialSnapshot {
                    didHandleInitialSnapshot = true

                    if opensRoomManagerWhenEmpty, rooms.isEmpty, onboardingWindow == nil {
                        showRoomManager()
                    }
                }
            }
        }

        invitationObserverTask = Task { @MainActor in
            for await invitations in invitationService.observeIncoming(uid: uid) {
                let previousIds = Set(appState.pendingInvitations.compactMap(\.id))
                for invitation in invitations {
                    guard let id = invitation.id, !previousIds.contains(id) else { continue }
                    LocalNotificationCenter.shared.notifyIncomingInvitation(invitation)
                }
                appState.pendingInvitations = invitations
            }
        }

        incomingMessageTask = Task { @MainActor in
            for await message in messageService.observeIncoming(uid: uid) {
                guard let id = message.id, shouldNotify(messageId: id, message: message) else {
                    continue
                }
                prefetchMessageVideo(message)
                rememberNotifiedMessage(id)
                LocalNotificationCenter.shared.notifyIncomingMessage(
                    senderNickname: message.senderNickname,
                    messageId: id
                )
            }
        }
    }

    private var roomSetupWasDeferred: Bool {
        UserDefaults.standard.bool(forKey: PingPreferenceKeys.roomSetupDeferred)
    }

    @objc private func toggleMirrorAction() {
        // Status-menu action — defaults to face_only (Option+P behavior)
        toggleMirror(mode: .faceOnly)
    }

    @objc private func toggleAppearanceModeAction() {
        toggleAppearanceMode()
    }

    private func toggleAppearanceMode() {
        PingAppearanceMode.toggleLightDark()
    }

    private func toggleMirror(mode: CaptureMode) {
        if mirrorWindow != nil, currentMirrorMode == mode {
            // Same-mode toggle → close
            closeMirrorWindow()
            return
        }
        if mirrorWindow != nil {
            // Different mode → close and re-open in new mode
            closeMirrorWindow()
        }
        currentMirrorMode = mode
        showMirror()
    }

    private func showMirror() {
        let mode = currentMirrorMode ?? .faceOnly
        let screen = NSScreen.main ?? NSScreen.screens.first!
        let size: NSSize = (mode == .faceOnly)
            ? MirrorWindow.faceOnlySize
            : MirrorWindow.sizeForScreenFace(on: screen)
        let origin = MirrorWindow.loadLastPosition(for: size)

        let window = MirrorWindow(captureMode: mode, initialSize: size, origin: origin)
        let view = MirrorView(
            camera: camera,
            screenCapture: screenCapture,
            captureMode: mode,
            viewModel: mirrorViewModel,
            appState: appState,
            windowOrigin: { [weak window] in window?.frame.origin ?? .zero },
            onClose: { [weak self] in
                self?.closeMirrorWindow()
            },
            onSend: { [weak self] tempURL, position, targets in
                try await self?.sendVideo(tempURL: tempURL, position: position, targets: targets)
            }
        )
        let host = NSHostingView(rootView: view)
        host.frame = NSRect(origin: .zero, size: size)
        window.contentView = host
        mirrorWindow = window

        mirrorViewModel.reset()
        mirrorWindow?.ensureVisibleOnCurrentScreen()
        startCameraForMirrorPresentation()
        if mode == .screenFace {
            Task {
                await screenCapture.startPreview(on: window.screen ?? screen)
            }
        }
        mirrorWindow?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    private func startCameraForMirrorPresentation() {
        cameraStartTask?.cancel()
        cameraStartTask = Task { @MainActor in
            guard !Task.isCancelled else { return }
            await camera.startWithAudio()
        }
    }

    private func closeMirrorWindow() {
        cameraStartTask?.cancel()
        cameraStartTask = nil
        mirrorWindow?.savePosition()
        mirrorWindow?.orderOut(nil)
        camera.stop()
        Task { await screenCapture.stop() }
        currentMirrorMode = nil
    }

    private func sendVideo(tempURL: URL, position: MirrorPosition, targets: [Room]) async throws {
        guard let currentUser = appState.currentUser,
              let senderUid = currentUser.id else {
            throw PingError.currentUserMissing
        }

        let localVideoURL: URL
        let shouldRemoveLocalVideoAfterSend: Bool
        if LocalArchive.saveSentEnabled {
            let storedURL: URL
            if targets.count == 1, let room = targets.first {
                storedURL = LocalArchive.sentURL(to: archiveName(for: room))
            } else {
                storedURL = LocalArchive.allPartnersSentURL()
            }

            LocalArchive.ensureFolders()
            if FileManager.default.fileExists(atPath: storedURL.path) {
                try? FileManager.default.removeItem(at: storedURL)
            }
            try FileManager.default.moveItem(at: tempURL, to: storedURL)
            localVideoURL = storedURL
            shouldRemoveLocalVideoAfterSend = false
        } else {
            localVideoURL = tempURL
            shouldRemoveLocalVideoAfterSend = true
        }

        do {
            try await messageService.send(.init(
                rooms: targets,
                localVideoURL: localVideoURL,
                mirrorPosition: position,
                senderUid: senderUid,
                senderNickname: currentUser.nickname
            ))
        } catch {
            if shouldRemoveLocalVideoAfterSend {
                try? FileManager.default.removeItem(at: localVideoURL)
            }
            throw error
        }

        if shouldRemoveLocalVideoAfterSend {
            try? FileManager.default.removeItem(at: localVideoURL)
        }
    }

    private func partnerName(in room: Room) -> String {
        guard let myUid = appState.currentUser?.id else { return "demo" }
        return room.memberNicknames.first(where: { $0.key != myUid })?.value ?? "demo"
    }

    private func archiveName(for room: Room) -> String {
        guard let myUid = appState.currentUser?.id else { return room.name }
        let otherNames = room.memberUids
            .filter { $0 != myUid }
            .compactMap { room.memberNicknames[$0] }

        if otherNames.count == 1 {
            return otherNames[0]
        }

        return room.name
    }

    private func playMessage(messageId: String) {
        Task { @MainActor in
            do {
                guard let message = try await messageService.get(messageId: messageId) else { return }
                let localURL = try await cachedVideoURL(for: message)

                let screen = NSScreen.main?.visibleFrame ?? .zero
                let center = ScreenCoordinates.denormalize(position: message.mirrorPosition, in: screen)
                let origin = ScreenCoordinates.clamp(
                    point: NSPoint(x: center.x - PlaybackWindow.size.width / 2,
                                   y: center.y - PlaybackWindow.size.height / 2),
                    windowSize: PlaybackWindow.size,
                    inSafeArea: screen
                )

                let windowId = UUID()
                let window = PlaybackWindow(
                    videoURL: localURL,
                    atScreenPoint: origin,
                    onFirstPlayEnd: { [weak self] in
                        Task { @MainActor in
                            try? await self?.messageService.markSeen(messageId: messageId)
                        }
                    },
                    onDone: { [weak self] in
                        Task { @MainActor in
                            if !LocalArchive.saveReceivedEnabled {
                                try? FileManager.default.removeItem(at: localURL)
                                self?.playbackCache[messageId] = nil
                            }
                            self?.playbackWindows.removeAll { $0.pingWindowId == windowId }
                        }
                    }
                )
                window.pingWindowId = windowId
                playbackWindows.append(window)
                window.fadeIn()
            } catch {
                NSLog("Playback failed: \(error)")
            }
        }
    }

    private func prefetchMessageVideo(_ message: VideoMessage) {
        guard let messageId = message.id,
              playbackCache[messageId] == nil,
              playbackPrefetchTasks[messageId] == nil else {
            return
        }

        let task = Task { @MainActor [weak self] () throws -> URL in
            guard let self else { throw CancellationError() }
            return try await self.downloadMessageVideo(message)
        }
        playbackPrefetchTasks[messageId] = task

        Task { @MainActor [weak self] in
            do {
                let url = try await task.value
                self?.playbackCache[messageId] = url
            } catch {
                NSLog("Video prefetch failed: \(error)")
            }
            self?.playbackPrefetchTasks[messageId] = nil
        }
    }

    private func cachedVideoURL(for message: VideoMessage) async throws -> URL {
        guard let messageId = message.id else {
            return try await downloadMessageVideo(message)
        }

        if let cachedURL = playbackCache[messageId],
           FileManager.default.fileExists(atPath: cachedURL.path) {
            return cachedURL
        }

        if let prefetchTask = playbackPrefetchTasks[messageId] {
            let url = try await prefetchTask.value
            playbackCache[messageId] = url
            return url
        }

        let url = try await downloadMessageVideo(message)
        playbackCache[messageId] = url
        return url
    }

    private func downloadMessageVideo(_ message: VideoMessage) async throws -> URL {
        let localURL = playbackLocalURL(for: message)
        if FileManager.default.fileExists(atPath: localURL.path) {
            return localURL
        }

        if LocalArchive.saveReceivedEnabled {
            LocalArchive.ensureFolders()
        }
        try await storageService.downloadVideo(from: message.videoUrl, to: localURL)
        return localURL
    }

    private func playbackLocalURL(for message: VideoMessage) -> URL {
        if LocalArchive.saveReceivedEnabled {
            return LocalArchive.receivedURL(from: message.senderNickname, date: message.createdAt ?? Date())
        }

        let fileName = message.id ?? UUID().uuidString
        return FileManager.default.temporaryDirectory
            .appendingPathComponent("ping-received-\(fileName).mp4")
    }

    private func showSetupError(_ error: Error) {
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = "Ping 초기 설정을 열 수 없습니다"
        alert.informativeText = error.localizedDescription
        alert.addButton(withTitle: "확인")
        NSApp.activate(ignoringOtherApps: true)
        alert.runModal()
    }

    private func showOnboarding(uid: String) {
        if let onboardingWindow {
            onboardingWindow.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        let viewModel = PairingViewModel()
        let view = PairingView(viewModel: viewModel, excludingUid: uid) { [weak self] completion in
            Task { @MainActor in
                guard let self else { return }
                guard !viewModel.isCompleting else { return }
                viewModel.isCompleting = true
                viewModel.errorMessage = nil
                do {
                    try await self.userService.upsert(uid: uid, nickname: completion.nickname)
                    self.appState.currentUser = try await self.userService.get(uid: uid)

                    let shouldOpenInviteSearch: Bool
                    switch completion.action {
                    case .createRoom(let roomName):
                        UserDefaults.standard.set(false, forKey: PingPreferenceKeys.roomSetupDeferred)
                        _ = try await self.roomService.createRoom(
                            name: roomName,
                            ownerUid: uid,
                            ownerNickname: completion.nickname
                        )
                        shouldOpenInviteSearch = true
                    case .joinRoom(let room):
                        UserDefaults.standard.set(false, forKey: PingPreferenceKeys.roomSetupDeferred)
                        if let roomId = room.id {
                            try await self.roomService.joinRoom(
                                roomId: roomId,
                                uid: uid,
                                nickname: completion.nickname
                            )
                        }
                        shouldOpenInviteSearch = false
                    case .later:
                        UserDefaults.standard.set(true, forKey: PingPreferenceKeys.roomSetupDeferred)
                        shouldOpenInviteSearch = false
                    }

                    self.startObservers(
                        uid: uid,
                        opensRoomManagerWhenEmpty: completion.action != .later
                    )
                    self.runCleanup(uid: uid)
                    self.onboardingWindow?.close()
                    self.onboardingWindow = nil
                    if let token = self.pendingInviteToken {
                        self.pendingInviteToken = nil
                        self.acceptInviteLink(token: token)
                    } else if shouldOpenInviteSearch {
                        self.presentRoomManager(initialTab: .search, searchInitialTab: .users)
                    }
                } catch {
                    viewModel.isCompleting = false
                    viewModel.errorMessage = error.localizedDescription
                    self.appState.backendStatusMessage = error.localizedDescription
                }
            }
        }

        onboardingWindow = OnboardingWindow(rootView: view)
        onboardingWindow?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    @objc private func showRoomManager() {
        presentRoomManager()
    }

    private func presentRoomManager(
        initialTab: RoomManagerTab = .rooms,
        searchInitialTab: RoomSearchTab = .rooms
    ) {
        let needsSpecificTab = initialTab != .rooms || searchInitialTab != .rooms
        if let roomManagerWindow, !roomManagerWindow.isVisible || needsSpecificTab {
            roomManagerWindow.close()
            self.roomManagerWindow = nil
        }

        if roomManagerWindow == nil {
            let view = RoomManagerView(
                appState: appState,
                roomService: roomService,
                invitationService: invitationService,
                initialTab: initialTab,
                searchInitialTab: searchInitialTab,
                onCopyInviteLink: { [weak self] room in
                    self?.copyInviteLink(for: room)
                },
                onJoinInviteLink: { [weak self] token in
                    self?.acceptInviteLink(token: token)
                },
                onInvite: { [weak self] user in
                    self?.handleInvite(user: user)
                }
            )
            roomManagerWindow = RoomManagerWindow(rootView: view)
        }

        roomManagerWindow?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    @objc private func showSettings() {
        if settingsWindow == nil {
            settingsWindow = SettingsWindow(rootView: SettingsView().environmentObject(appState))
        }

        settingsWindow?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    private func handleInvite(user: PingUser) {
        guard let currentUser = appState.currentUser,
              let theirUid = user.id else {
            return
        }

        Task {
            do {
                let roomName = "\(currentUser.nickname) ↔ \(user.nickname)"
                let room = try await invitationService.inviteUser(
                    toUid: theirUid,
                    fromNickname: currentUser.nickname,
                    roomName: roomName
                )
                insertOrReplaceRoom(room)
            } catch {
                appState.backendStatusMessage = error.localizedDescription
            }
        }
    }

    private func copyInviteLink(for room: Room) {
        guard let roomId = room.id else { return }

        Task {
            do {
                let link = try await invitationService.createInviteLink(roomId: roomId)
                let url = PingInviteLink.url(for: link.token).absoluteString
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(url, forType: .string)
                showTransientAlert(
                    title: "초대 링크를 복사했습니다",
                    message: "상대가 앱을 설치한 뒤 이 링크를 열면 룸에 참여할 수 있습니다.\n\n\(url)"
                )
            } catch {
                appState.backendStatusMessage = error.localizedDescription
                showTransientAlert(title: "초대 링크를 만들 수 없습니다", message: error.localizedDescription)
            }
        }
    }

    private func acceptInviteLink(token: String) {
        guard let currentUser = appState.currentUser else {
            pendingInviteToken = token
            startBootstrapTaskIfNeeded()
            return
        }

        Task {
            do {
                let room = try await invitationService.acceptInviteLink(
                    token: token,
                    nickname: currentUser.nickname
                )
                insertOrReplaceRoom(room)
                showTransientAlert(title: "룸에 참여했습니다", message: "\(room.name)에 참여했습니다.")
                showRoomManager()
            } catch {
                appState.backendStatusMessage = error.localizedDescription
                showTransientAlert(title: "초대 링크를 사용할 수 없습니다", message: error.localizedDescription)
            }
        }
    }

    private func insertOrReplaceRoom(_ room: Room) {
        if let roomId = room.id,
           let index = appState.rooms.firstIndex(where: { $0.id == roomId }) {
            appState.rooms[index] = room
        } else {
            appState.rooms.append(room)
        }

        appState.rooms.sort { lhs, rhs in
            lhs.name.localizedStandardCompare(rhs.name) == .orderedAscending
        }
    }

    private func showTransientAlert(title: String, message: String) {
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = message
        alert.addButton(withTitle: "확인")
        NSApp.activate(ignoringOtherApps: true)
        alert.runModal()
    }

    private func acceptInvitation(inviteId: String) {
        guard let invitation = appState.pendingInvitations.first(where: { $0.id == inviteId }),
              let currentUser = appState.currentUser,
              let uid = currentUser.id else {
            showRoomManager()
            return
        }

        Task {
            try? await invitationService.accept(
                invitation: invitation,
                myUid: uid,
                myNickname: currentUser.nickname,
                roomService: roomService
            )
        }
    }

    private func rejectInvitation(inviteId: String) {
        Task {
            try? await invitationService.reject(inviteId: inviteId)
        }
    }

    private func shouldNotify(messageId: String, message: VideoMessage) -> Bool {
        if notifiedMessageIds().contains(messageId) {
            return false
        }

        if message.expiresAt < Date() {
            return false
        }

        guard let createdAt = message.createdAt else { return false }
        if createdAt >= appStartTime {
            return true
        }

        // Older uploaded messages are offline catch-up. Repeat notifications are
        // blocked by the persisted message-id set above.
        return true
    }

    private func notifiedMessageIds() -> Set<String> {
        Set(UserDefaults.standard.stringArray(forKey: notifiedMessageIdsKey) ?? [])
    }

    private func rememberNotifiedMessage(_ id: String) {
        var set = notifiedMessageIds()
        set.insert(id)
        var ids = Array(set)
        ids = Array(ids.suffix(300))
        UserDefaults.standard.set(ids, forKey: notifiedMessageIdsKey)
    }

    private func runCleanup(uid: String) {
        Task { @MainActor in
            do {
                try await cleanupService.run(uid: uid)
            } catch {
                NSLog("Cleanup failed: \(error)")
            }
        }
    }
}

private extension ProcessInfo {
    var isRunningUnitTests: Bool {
        environment["XCTestConfigurationFilePath"] != nil
    }
}
