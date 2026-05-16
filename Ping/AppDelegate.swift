import AppKit
import SwiftUI

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem?
    private var mirrorWindow: MirrorWindow?
    private var onboardingWindow: OnboardingWindow?
    private var roomManagerWindow: RoomManagerWindow?
    private var playbackWindows: [PlaybackWindow] = []

    private let appState = AppState.shared
    private let camera = CameraManager()
    private let mirrorViewModel = MirrorViewModel()
    private let messageService = MessageService()
    private let userService = UserService()
    private let roomService = RoomService()
    private let invitationService = InvitationService()
    private let storageService = StorageService()
    private let appStartTime = Date()
    private let notifiedMessageIdsKey = "ping.notifications.notifiedMessageIds"

    private var roomObserverTask: Task<Void, Never>?
    private var invitationObserverTask: Task<Void, Never>?
    private var incomingMessageTask: Task<Void, Never>?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        LocalArchive.ensureFolders()
        setupStatusBar()
        setupNotifications()
        setupHotkey()

        Task { await camera.configure() }
        Task { await bootstrapFirebase() }
    }

    func applicationWillTerminate(_ notification: Notification) {
        roomObserverTask?.cancel()
        invitationObserverTask?.cancel()
        incomingMessageTask?.cancel()
        camera.stop()
    }

    private func setupStatusBar() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        item.button?.image = NSImage(systemSymbolName: "circle.dotted.circle", accessibilityDescription: "Ping")
        item.button?.image?.isTemplate = true

        let menu = NSMenu()

        let status = NSMenuItem(title: "Ping", action: nil, keyEquivalent: "")
        status.isEnabled = false
        menu.addItem(status)

        let partner = NSMenuItem(title: "파트너: 없음", action: nil, keyEquivalent: "")
        partner.tag = 1001
        partner.isEnabled = false
        menu.addItem(partner)
        menu.addItem(NSMenuItem.separator())

        let send = NSMenuItem(title: "영상 보내기", action: #selector(toggleMirrorAction), keyEquivalent: "")
        send.target = self
        menu.addItem(send)

        let rooms = NSMenuItem(title: "내 룸…", action: #selector(showRoomManager), keyEquivalent: "")
        rooms.target = self
        menu.addItem(rooms)

        let settings = NSMenuItem(title: "설정…", action: #selector(showSettings), keyEquivalent: ",")
        settings.target = self
        menu.addItem(settings)
        menu.addItem(NSMenuItem.separator())
        menu.addItem(NSMenuItem(title: "종료", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))

        item.menu = menu
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
        HotkeyManager.shared.register { [weak self] in
            self?.toggleMirror()
        }
    }

    private func bootstrapFirebase() async {
        do {
            let uid = try await FirebaseClient.shared.bootstrap()
            let existing = try await userService.get(uid: uid)

            if let existing {
                try await userService.upsert(uid: uid, nickname: existing.nickname)
                appState.currentUser = try await userService.get(uid: uid) ?? existing
                startObservers(uid: uid)
                updateMenuPartner()
            } else {
                showOnboarding(uid: uid)
            }
        } catch {
            appState.backendStatusMessage = error.localizedDescription
            NSLog("Firebase bootstrap failed: \(error)")
        }
    }

    private func startObservers(uid: String) {
        roomObserverTask?.cancel()
        invitationObserverTask?.cancel()
        incomingMessageTask?.cancel()

        roomObserverTask = Task { @MainActor in
            for await rooms in roomService.observeMyRooms(uid: uid) {
                appState.rooms = rooms
                updateMenuPartner()
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
                rememberNotifiedMessage(id)
                LocalNotificationCenter.shared.notifyIncomingMessage(
                    senderNickname: message.senderNickname,
                    messageId: id
                )
            }
        }
    }

    @objc private func toggleMirrorAction() {
        toggleMirror()
    }

    private func toggleMirror() {
        if let window = mirrorWindow, window.isVisible {
            window.savePosition()
            window.orderOut(nil)
            return
        }

        if mirrorWindow == nil {
            let window = MirrorWindow(rootView: EmptyView())
            let view = MirrorView(
                camera: camera,
                viewModel: mirrorViewModel,
                appState: appState,
                windowOrigin: { [weak window] in window?.frame.origin ?? .zero },
                onClose: { [weak self] in
                    self?.mirrorWindow?.savePosition()
                    self?.mirrorWindow?.orderOut(nil)
                },
                onSend: { [weak self] tempURL, position, targets in
                    try await self?.sendVideo(tempURL: tempURL, position: position, targets: targets)
                }
            )
            let host = NSHostingView(rootView: view)
            host.frame = NSRect(origin: .zero, size: MirrorWindow.size)
            window.contentView = host
            mirrorWindow = window
        }

        mirrorViewModel.reset()
        mirrorWindow?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    private func sendVideo(tempURL: URL, position: MirrorPosition, targets: [Room]) async throws {
        guard let currentUser = appState.currentUser,
              let senderUid = currentUser.id else {
            throw PingError.currentUserMissing
        }

        let localVideoURL: URL
        if LocalArchive.localSaveEnabled {
            let storedURL: URL
            if targets.count == 1, let room = targets.first {
                storedURL = LocalArchive.sentURL(to: partnerName(in: room))
            } else {
                storedURL = LocalArchive.allPartnersSentURL()
            }

            LocalArchive.ensureFolders()
            if FileManager.default.fileExists(atPath: storedURL.path) {
                try? FileManager.default.removeItem(at: storedURL)
            }
            try FileManager.default.moveItem(at: tempURL, to: storedURL)
            localVideoURL = storedURL
        } else {
            localVideoURL = tempURL
        }

        try await messageService.send(.init(
            rooms: targets,
            localVideoURL: localVideoURL,
            mirrorPosition: position,
            senderUid: senderUid,
            senderNickname: currentUser.nickname
        ))

        if !LocalArchive.localSaveEnabled {
            try? FileManager.default.removeItem(at: localVideoURL)
        }
    }

    private func partnerName(in room: Room) -> String {
        guard let myUid = appState.currentUser?.id else { return "demo" }
        return room.memberNicknames.first(where: { $0.key != myUid })?.value ?? "demo"
    }

    private func playMessage(messageId: String) {
        Task { @MainActor in
            do {
                guard let message = try await messageService.get(messageId: messageId) else { return }
                let localURL: URL
                if LocalArchive.localSaveEnabled {
                    LocalArchive.ensureFolders()
                    localURL = LocalArchive.receivedURL(from: message.senderNickname)
                } else {
                    localURL = FileManager.default.temporaryDirectory
                        .appendingPathComponent("ping-received-\(UUID().uuidString).mp4")
                }
                try await storageService.downloadVideo(from: message.videoUrl, to: localURL)

                let screen = NSScreen.main?.visibleFrame ?? .zero
                let center = ScreenCoordinates.denormalize(position: message.mirrorPosition, in: screen)
                let origin = ScreenCoordinates.clamp(
                    point: NSPoint(x: center.x - PlaybackWindow.size.width / 2,
                                   y: center.y - PlaybackWindow.size.height / 2),
                    windowSize: PlaybackWindow.size,
                    inSafeArea: screen
                )

                let windowId = UUID()
                let window = PlaybackWindow(videoURL: localURL, atScreenPoint: origin) { [weak self] in
                    Task { @MainActor in
                        try? await self?.messageService.markSeen(messageId: messageId)
                        if !LocalArchive.localSaveEnabled {
                            try? FileManager.default.removeItem(at: localURL)
                        }
                        self?.playbackWindows.removeAll { $0.pingWindowId == windowId }
                    }
                }
                window.pingWindowId = windowId
                playbackWindows.append(window)
                window.fadeIn()
            } catch {
                NSLog("Playback failed: \(error)")
            }
        }
    }

    private func showOnboarding(uid: String) {
        let viewModel = PairingViewModel()
        let view = PairingView(viewModel: viewModel) { [weak self] nickname, firstRoomName in
            Task { @MainActor in
                guard let self else { return }
                do {
                    try await self.userService.upsert(uid: uid, nickname: nickname)
                    self.appState.currentUser = try await self.userService.get(uid: uid)

                    if let firstRoomName, !firstRoomName.isEmpty {
                        _ = try await self.roomService.createRoom(
                            name: firstRoomName,
                            ownerUid: uid,
                            ownerNickname: nickname
                        )
                    }

                    self.startObservers(uid: uid)
                    self.onboardingWindow?.close()
                    self.onboardingWindow = nil
                } catch {
                    self.appState.backendStatusMessage = error.localizedDescription
                }
            }
        }

        onboardingWindow = OnboardingWindow(rootView: view)
        onboardingWindow?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    @objc private func showRoomManager() {
        if roomManagerWindow == nil {
            let view = RoomManagerView(
                appState: appState,
                roomService: roomService,
                invitationService: invitationService,
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
        NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    private func handleInvite(user: PingUser) {
        guard let currentUser = appState.currentUser,
              let myUid = currentUser.id,
              let theirUid = user.id else {
            return
        }

        Task {
            do {
                let roomName = "\(currentUser.nickname) ↔ \(user.nickname)"
                let room = try await roomService.createRoom(
                    name: roomName,
                    ownerUid: myUid,
                    ownerNickname: currentUser.nickname
                )
                guard let roomId = room.id else { return }
                try await invitationService.send(
                    fromUid: myUid,
                    fromNickname: currentUser.nickname,
                    toUid: theirUid,
                    roomId: roomId,
                    roomName: roomName
                )
            } catch {
                appState.backendStatusMessage = error.localizedDescription
            }
        }
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

    private func updateMenuPartner() {
        guard let menu = statusItem?.menu,
              let item = menu.item(withTag: 1001) else {
            return
        }

        if let room = appState.defaultRoom {
            item.title = "파트너: \(partnerName(in: room))"
        } else {
            item.title = "파트너: 없음"
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
}
