import AppKit
import Combine
import OSLog
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
    private var playbackPrefetchTasks: [String: Task<URL?, Never>] = [:]

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
    private let chatRealtime = ChatRealtimeService()
    private let chatMessageService = ChatMessageService()
    private let desktopPresenceService = DesktopPresenceService()
    private let appStartTime = Date()
    private let ledger = NotificationLedger()

    private var notifiedChatMessageIds: Set<String> = []
    private var isSwitchingAccount = false
    private var cancellables: Set<AnyCancellable> = []

    private var roomObserverTask: Task<Void, Never>?
    private var invitationObserverTask: Task<Void, Never>?
    private var incomingMessageTask: Task<Void, Never>?
    private var chatCatchUpTask: Task<Void, Never>?
    private var desktopPresenceTask: Task<Void, Never>?
    private var bootstrapTask: Task<Void, Never>?
    private var bootstrapRetryTask: Task<Void, Never>?
    private var bootstrapFailureCount = 0
    private var cameraStartTask: Task<Void, Never>?
    private var pendingInviteToken: String?
    private var currentMirrorMode: CaptureMode?

    private var showsOnboardingForQA: Bool {
        #if DEBUG
        ProcessInfo.processInfo.arguments.contains("--show-onboarding")
        #else
        false
        #endif
    }

    func applicationWillFinishLaunching(_ notification: Notification) {
        if !ProcessInfo.processInfo.isRunningUnitTests, shouldYieldToRunningInstance() {
            // exit(0)이어야 launchd가 비정상 종료로 보지 않는다. 0이 아니면 KeepAlive가
            // 곧바로 다시 띄워 무한 루프가 된다.
            exit(0)
        }

        enforceAccessoryActivationPolicy()
    }

    private func shouldYieldToRunningInstance() -> Bool {
        guard let bundleIdentifier = Bundle.main.bundleIdentifier else { return false }

        return SingleInstanceGuard.shouldYield(
            runningPIDs: SingleInstanceGuard.runningPIDs(forBundleIdentifier: bundleIdentifier),
            currentPID: ProcessInfo.processInfo.processIdentifier
        )
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        enforceAccessoryActivationPolicySoon()
        PingAppearanceMode.applyCurrent()
        LocalArchive.migrateLegacyPreferencesIfNeeded()
        LocalArchive.ensureFolders()
        setupStatusBar()
        setupNotifications()
        setupAccountSwitching()
        setupHotkey()

        if !ProcessInfo.processInfo.isRunningUnitTests {
            AutoStartController.shared.applyPolicyAtLaunch()

            if showsOnboardingForQA {
                showOnboardingPreviewForQA()
                return
            }

            UpdaterController.shared.start()
            startBootstrapTaskIfNeeded()
        }
    }

    func applicationDidBecomeActive(_ notification: Notification) {
        enforceAccessoryActivationPolicySoon()
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        enforceAccessoryActivationPolicySoon()
        return false
    }

    func applicationWillTerminate(_ notification: Notification) {
        bootstrapTask?.cancel()
        bootstrapRetryTask?.cancel()
        roomObserverTask?.cancel()
        invitationObserverTask?.cancel()
        incomingMessageTask?.cancel()
        desktopPresenceTask?.cancel()
        cancelPlaybackPrefetches()
        cameraStartTask?.cancel()
        camera.stop()
        Task { await chatRealtime.unsubscribeAll() }
        Task { await desktopPresenceService.clear() }
    }

    func application(_ application: NSApplication, open urls: [URL]) {
        guard let token = urls.compactMap(PingInviteLink.token(from:)).first else {
            return
        }

        acceptInviteLink(token: token)
    }

    private func enforceAccessoryActivationPolicy() {
        NSApp.setActivationPolicy(.accessory)
    }

    private func enforceAccessoryActivationPolicySoon() {
        enforceAccessoryActivationPolicy()
        Task { @MainActor [weak self] in
            await Task.yield()
            self?.enforceAccessoryActivationPolicy()
            try? await Task.sleep(nanoseconds: 500_000_000)
            self?.enforceAccessoryActivationPolicy()
        }
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
        item.menu?.delegate = self
        statusItem = item
    }

    private func setupNotifications() {
        LocalNotificationCenter.shared.configure()

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
        LocalNotificationCenter.shared.onViewChatMessage = { [weak self] chatId, roomId in
            LocalNotificationCenter.shared.clearDeliveredNotifications(roomId: roomId)
            ClientEventService.shared.log("chat_notification_clicked", properties: ["room_id": roomId])
            self?.appState.pendingRoomFocusId = roomId
            self?.showRoomManager()
        }
        LocalNotificationCenter.shared.onCheckForUpdates = {
            UpdaterController.shared.checkForUpdates(nil)
        }

        if !ProcessInfo.processInfo.isRunningUnitTests {
            chatRealtime.$lastEvent
                .compactMap { $0 }
                .receive(on: DispatchQueue.main)
                .sink { [weak self] event in
                    self?.handleChatRealtimeEvent(event)
                }
                .store(in: &cancellables)

            appState.$lastSelectedRoomId
                .removeDuplicates()
                .sink { [weak self] _ in
                    guard let self, self.desktopPresenceTask != nil else { return }
                    Task { @MainActor in
                        await self.refreshDesktopPresence()
                    }
                }
                .store(in: &cancellables)
        }
    }

    private func setupHotkey() {
        HotkeyManager.shared.register(
            onCaptureFace: { [weak self] in self?.toggleMirror(mode: .faceOnly) },
            onAppearanceToggle: { [weak self] in self?.toggleAppearanceMode() },
            onCaptureScreenFace: { [weak self] in self?.toggleMirror(mode: .screenFace) },
            onHistoryToggle: { [weak self] in self?.toggleRoomManager() }
        )
    }

    private func startBootstrapTaskIfNeeded() {
        guard bootstrapTask == nil else { return }

        bootstrapRetryTask?.cancel()
        bootstrapRetryTask = nil

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
            bootstrapFailureCount = 0
            bootstrapRetryTask?.cancel()
            bootstrapRetryTask = nil
            appState.backendStatusMessage = nil

            if let existing {
                try await userService.upsert(uid: uid, nickname: existing.nickname)
                appState.currentUser = try await userService.get(uid: uid) ?? existing
                SupabaseClient.shared.updateActiveNickname(existing.nickname)
                MultiAccountGate.updateUnlock(forNickname: existing.nickname)
                ClientEventService.shared.log("app_launched")
                startObservers(uid: uid, opensRoomManagerWhenEmpty: !roomSetupWasDeferred)
                runCleanup(uid: uid)
                consumePendingInviteTokenIfAvailable()
            } else {
                showOnboarding(uid: uid)
            }
        } catch {
            NSLog("Backend bootstrap failed: \(error)")
            if BackendRetryPolicy.shouldRetryBootstrap(after: error) {
                scheduleBackendBootstrapRetry(after: error)
                return
            }

            appState.backendStatusMessage = error.localizedDescription
            showSetupError(error)
        }
    }

    private func scheduleBackendBootstrapRetry(after error: Error) {
        bootstrapFailureCount += 1
        let delay = BackendRetryPolicy.delay(forFailureCount: bootstrapFailureCount)
        appState.backendStatusMessage = "네트워크 연결을 기다리는 중입니다. \(Int(delay))초 후 다시 시도합니다."
        NSLog("Backend bootstrap transient failure; retrying in \(Int(delay))s: \(error)")

        bootstrapRetryTask?.cancel()
        bootstrapRetryTask = Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
            guard !Task.isCancelled else { return }
            self?.bootstrapRetryTask = nil
            self?.startBootstrapTaskIfNeeded()
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
        cancelPlaybackPrefetches()
        seedVideoNotificationLedgerFromHistoryCache(uid: uid)
        startDesktopPresenceHeartbeat()

        roomObserverTask = Task { @MainActor in
            var didHandleInitialSnapshot = false

            for await rooms in roomService.observeMyRooms(uid: uid) {
                appState.rooms = rooms
                Task { @MainActor in
                    let roomIds = rooms.compactMap(\.id)
                    if let url = try? SupabaseClient.shared.configURL,
                       let anonKey = try? SupabaseClient.shared.configAnonKey {
                        let token = await SupabaseClient.shared.currentAccessToken()
                        await self.chatRealtime.subscribe(
                            roomIds: roomIds,
                            supabaseURL: url,
                            anonKey: anonKey,
                            accessToken: token
                        )
                    }
                }
                if !rooms.isEmpty {
                    UserDefaults.standard.set(false, forKey: PingPreferenceKeys.roomSetupDeferred)
                }

                if !didHandleInitialSnapshot {
                    didHandleInitialSnapshot = true

                    if opensRoomManagerWhenEmpty, rooms.isEmpty, onboardingWindow == nil {
                        showRoomManager()
                    }

                    // 룸 목록이 채워진 뒤 캐치업을 실행해야 묶음 알림에 실제 룸 이름이 들어간다.
                    catchUpChatNotifications(uid: uid)
                }
            }
        }

        invitationObserverTask = Task { @MainActor in
            for await invitations in invitationService.observeIncoming(uid: uid) {
                for invitation in invitations {
                    guard let id = invitation.id, !ledger.contains(.invite, uid: uid, id: id) else { continue }
                    ledger.remember(.invite, uid: uid, id: id)
                    LocalNotificationCenter.shared.notifyIncomingInvitation(invitation)
                }
                appState.pendingInvitations = invitations
            }
        }

        incomingMessageTask = Task { @MainActor in
            for await message in messageService.observeIncoming(uid: uid) {
                guard let id = message.id, shouldNotify(messageId: id, uid: uid, message: message) else {
                    continue
                }
                await prefetchMessageVideo(message)
                let didScheduleNotification = await LocalNotificationCenter.shared.notifyIncomingMessage(
                    senderNickname: message.senderNickname,
                    messageId: id,
                    roomId: message.roomId
                )
                guard didScheduleNotification else { continue }
                ledger.remember(.video, uid: uid, id: id)
                try? await messageService.markNotified(messageId: id)
            }
        }
    }

    private func startDesktopPresenceHeartbeat() {
        desktopPresenceTask?.cancel()
        desktopPresenceTask = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                await self?.refreshDesktopPresence()
                try? await Task.sleep(nanoseconds: 15_000_000_000)
            }
        }
    }

    private func stopDesktopPresenceHeartbeat(clear: Bool = true) {
        desktopPresenceTask?.cancel()
        desktopPresenceTask = nil
        if clear {
            Task { @MainActor [weak self] in
                await self?.desktopPresenceService.clear()
            }
        }
    }

    private func refreshDesktopPresence() async {
        do {
            try await desktopPresenceService.update(activeRoomId: visibleRoomIdForPresence)
        } catch {
            NSLog("Desktop presence heartbeat failed: \(error)")
        }
    }

    private var visibleRoomIdForPresence: String? {
        guard let roomManagerWindow, roomManagerWindow.isVisible else { return nil }
        return appState.lastSelectedRoomId
    }

    private func seedVideoNotificationLedgerFromHistoryCache(uid: String) {
        for id in HistoryCacheService.shared.cachedVideoMessageIds() {
            ledger.remember(.video, uid: uid, id: id)
        }
    }

    private var roomSetupWasDeferred: Bool {
        UserDefaults.standard.bool(forKey: PingPreferenceKeys.roomSetupDeferred)
    }

    @objc private func toggleMirrorAction() {
        // Status-menu action — defaults to face_only (Option+P behavior)
        toggleMirror(mode: .faceOnly)
    }

    @objc func toggleScreenFaceAction() {
        toggleMirror(mode: .screenFace)
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

        switch mode {
        case .faceOnly:
            currentMirrorMode = mode
            showMirror()
        case .screenFace:
            Task { [weak self] in
                guard let self else { return }
                var status = await ScreenCapturePermission.currentStatus()

                // If denied, ask the system to surface the prompt once.
                // After a permanent denial, CGRequestScreenCaptureAccess returns
                // immediately without prompting — user must grant via Settings.
                if status != .authorized {
                    _ = ScreenCapturePermission.requestPermission()
                    // Re-check after the request returns.
                    status = await ScreenCapturePermission.currentStatus()
                }

                if status == .authorized {
                    self.currentMirrorMode = mode
                    self.showMirror()
                } else {
                    self.notifyScreenRecordingPermissionRequired()
                }
            }
        }
    }

    private func notifyScreenRecordingPermissionRequired() {
        let alert = NSAlert()
        alert.messageText = "화면 녹화 권한이 필요합니다"
        alert.informativeText = "화면+얼굴 모드를 사용하려면 시스템 설정에서 Ping에 화면 녹화 권한을 부여해주세요."
        alert.addButton(withTitle: "시스템 설정 열기")
        alert.addButton(withTitle: "닫기")
        ForegroundPresenter.activateApp()
        let response = alert.runModal()
        if response == .alertFirstButtonReturn {
            ScreenCapturePermission.openSystemSettings()
        }
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
            captureScreenFrame: screen.frame,
            previewSize: size,
            viewModel: mirrorViewModel,
            appState: appState,
            windowOrigin: { [weak window] in window?.frame.origin ?? .zero },
            onClose: { [weak self] in
                self?.closeMirrorWindow()
            },
            onSend: { [weak self] url, position, rooms, mode, aspect in
                try await self?.sendVideo(tempURL: url, position: position, targets: rooms, captureMode: mode, aspectRatio: aspect)
            }
        )
        let host = NSHostingView(rootView: view)
        host.frame = NSRect(origin: .zero, size: size)
        window.contentView = host
        mirrorWindow = window

        mirrorViewModel.reset()
        mirrorWindow?.ensureVisibleOnCurrentScreen()
        startCameraForMirrorPresentation()
        ForegroundPresenter.present(mirrorWindow)
        if mode == .screenFace {
            let previewScreen = window.screen ?? screen
            Task { [weak self, weak window] in
                await Task.yield()
                guard let self,
                      let window,
                      window === self.mirrorWindow else { return }
                await self.screenCapture.startPreview(on: previewScreen)
            }
        }
        ClientEventService.shared.log("mirror_opened", properties: ["mode": mode.rawValue])
    }

    private func startCameraForMirrorPresentation() {
        cameraStartTask?.cancel()
        cameraStartTask = Task { @MainActor in
            guard !Task.isCancelled else { return }
            await camera.startWithAudio()
        }
    }

    private func closeMirrorWindow() {
        // 1. Clean up any reviewing temp file before resetting state.
        if case .reviewing(let tempURL) = mirrorViewModel.state {
            try? FileManager.default.removeItem(at: tempURL)
        }

        // 2. Reset shared view model so the next mirror starts clean.
        mirrorViewModel.reset()
        appState.sendMode = .singlePartner

        // 3. Save position and tear down the window, detaching NSHostingView so .onDisappear fires.
        mirrorWindow?.savePosition()
        mirrorWindow?.contentView = nil
        mirrorWindow?.orderOut(nil)
        mirrorWindow = nil

        // 4. Cancel any in-flight camera start, wait for it, then stop the session.
        let pendingStart = cameraStartTask
        cameraStartTask?.cancel()
        cameraStartTask = nil

        Task { @MainActor in
            _ = await pendingStart?.value
            camera.stop()
            await screenCapture.stop()
        }

        currentMirrorMode = nil
    }

    private func sendVideo(tempURL: URL, position: MirrorPosition, targets: [Room], captureMode: CaptureMode = .faceOnly, aspectRatio: Double = 1.0) async throws {
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
                senderNickname: currentUser.nickname,
                captureMode: captureMode,
                aspectRatio: aspectRatio,
                allowsLocalSave: LocalArchive.allowRecipientsToSaveMyVideos
            ))
            ClientEventService.shared.log("ping_sent", properties: [
                "mode": captureMode.rawValue,
                "aspect_ratio": aspectRatio,
                "recipients_count": Set(targets.flatMap { $0.memberUids }).count
            ])
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
            ForegroundPresenter.activateApp()
            do {
                guard let message = try await messageService.get(messageId: messageId) else { return }
                let localURL = try await cachedVideoURL(for: message)
                let shouldKeepReceivedVideo = LocalArchive.saveReceivedEnabled && message.allowsLocalSave

                let screen = NSScreen.main ?? NSScreen.screens.first!
                let size = PlaybackWindow.size(for: message.captureMode, aspectRatio: message.aspectRatio, on: screen)
                let visibleFrame = screen.visibleFrame
                let center = ScreenCoordinates.denormalize(position: message.mirrorPosition, in: visibleFrame)
                let origin = ScreenCoordinates.clamp(
                    point: NSPoint(x: center.x - size.width / 2, y: center.y - size.height / 2),
                    windowSize: size,
                    inSafeArea: visibleFrame
                )

                let windowId = UUID()
                let window = PlaybackWindow(
                    videoURL: localURL,
                    mode: message.captureMode,
                    aspectRatio: message.aspectRatio,
                    atScreenPoint: origin,
                    screen: screen,
                    onFirstPlayEnd: { [weak self] in
                        Task { @MainActor in
                            try? await self?.messageService.markSeen(messageId: messageId)
                        }
                    },
                    onDone: { [weak self] in
                        Task { @MainActor in
                            if !shouldKeepReceivedVideo {
                                try? FileManager.default.removeItem(at: localURL)
                                self?.playbackCache[messageId] = nil
                            }
                            self?.playbackWindows.removeAll { $0.pingWindowId == windowId }
                        }
                    }
                )
                window.pingWindowId = windowId
                playbackWindows.append(window)
                ClientEventService.shared.log("ping_received_view", properties: [
                    "mode": message.captureMode.rawValue
                ])
                window.fadeIn()
            } catch {
                NSLog("Playback failed: \(error)")
            }
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

        if let prefetchTask = playbackPrefetchTasks[messageId],
           let prefetchedURL = await prefetchTask.value,
           FileManager.default.fileExists(atPath: prefetchedURL.path) {
            playbackCache[messageId] = prefetchedURL
            return prefetchedURL
        }

        let url = try await downloadMessageVideo(message)
        playbackCache[messageId] = url
        return url
    }

    @discardableResult
    private func prefetchMessageVideo(_ message: VideoMessage) async -> URL? {
        guard let messageId = message.id else {
            return try? await cachedVideoURL(for: message)
        }

        if let cachedURL = playbackCache[messageId],
           FileManager.default.fileExists(atPath: cachedURL.path) {
            return cachedURL
        }

        if let prefetchTask = playbackPrefetchTasks[messageId] {
            return await prefetchTask.value
        }

        let task = Task { @MainActor [weak self] () -> URL? in
            guard let self else { return nil }

            do {
                return try await self.cachedVideoURL(for: message)
            } catch {
                NSLog("Video prefetch failed: \(error)")
                return nil
            }
        }

        playbackPrefetchTasks[messageId] = task
        let url = await task.value
        playbackPrefetchTasks[messageId] = nil
        return url
    }

    private func cancelPlaybackPrefetches() {
        for task in playbackPrefetchTasks.values {
            task.cancel()
        }
        playbackPrefetchTasks.removeAll()
    }

    private func downloadMessageVideo(_ message: VideoMessage) async throws -> URL {
        let localURL = playbackLocalURL(for: message)
        if FileManager.default.fileExists(atPath: localURL.path) {
            return localURL
        }

        if LocalArchive.saveReceivedEnabled && message.allowsLocalSave {
            LocalArchive.ensureFolders()
        }
        try await storageService.downloadVideo(from: message.videoUrl, to: localURL)
        return localURL
    }

    private func playbackLocalURL(for message: VideoMessage) -> URL {
        if LocalArchive.saveReceivedEnabled && message.allowsLocalSave {
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
        ForegroundPresenter.activateApp()
        alert.runModal()
    }

    private func showOnboardingPreviewForQA() {
        if let onboardingWindow {
            ForegroundPresenter.present(onboardingWindow)
            return
        }

        let viewModel = PairingViewModel()
        let view = PairingView(viewModel: viewModel, excludingUid: "qa-preview") { [weak self] _ in
            Task { @MainActor in
                self?.onboardingWindow?.close()
                self?.onboardingWindow = nil
            }
        }

        onboardingWindow = OnboardingWindow(rootView: view)
        ForegroundPresenter.present(onboardingWindow)
    }

    private func showOnboarding(uid: String) {
        if let onboardingWindow {
            ForegroundPresenter.present(onboardingWindow)
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
                    SupabaseClient.shared.updateActiveNickname(completion.nickname)
                    MultiAccountGate.updateUnlock(forNickname: completion.nickname)

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
        ForegroundPresenter.present(onboardingWindow)
    }

    @objc private func showRoomManager() {
        presentRoomManager()
    }

    private func toggleRoomManager() {
        if let roomManagerWindow, roomManagerWindow.isVisible {
            roomManagerWindow.close()
            Task { @MainActor [weak self] in
                await self?.refreshDesktopPresence()
            }
            return
        }

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
                chatRealtime: chatRealtime,
                messageService: messageService,
                cacheService: HistoryCacheService.shared,
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

        ForegroundPresenter.present(roomManagerWindow)
        Task { @MainActor [weak self] in
            await self?.refreshDesktopPresence()
        }
    }

    @objc private func showSettings() {
        if settingsWindow == nil {
            settingsWindow = SettingsWindow(rootView: SettingsView().environmentObject(appState))
        }

        ForegroundPresenter.present(settingsWindow)
    }

    private func handleInvite(user: PingUser) {
        guard let currentUser = appState.currentUser,
              let theirUid = user.id else {
            return
        }

        Task {
            do {
                let roomName = RoomLimits.directRoomName(
                    myNickname: currentUser.nickname,
                    otherNickname: user.nickname
                )
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
    }

    private func showTransientAlert(title: String, message: String) {
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = message
        alert.addButton(withTitle: "확인")
        ForegroundPresenter.activateApp()
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

    @MainActor
    private func handleChatRealtimeEvent(_ event: ChatRealtimeService.Event) {
        guard case .chatInserted(let msg) = event else { return }
        guard msg.senderUid != appState.currentUser?.id else { return }
        guard let id = msg.id, !notifiedChatMessageIds.contains(id) else { return }
        notifiedChatMessageIds.insert(id)
        if notifiedChatMessageIds.count > 500 {
            notifiedChatMessageIds = Set(notifiedChatMessageIds.suffix(500))
        }

        // Suppress notification if RoomManagerWindow is visible AND that room is selected.
        let suppressed: Bool = {
            guard let window = roomManagerWindow, window.isVisible else { return false }
            return appState.pendingRoomFocusId == msg.roomId
                || appState.lastSelectedRoomId == msg.roomId
        }()

        if suppressed { return }

        let roomName = appState.rooms.first(where: { $0.id == msg.roomId })?.name ?? "룸"
        LocalNotificationCenter.shared.notifyIncomingChat(msg, roomName: roomName)
    }

    private func shouldNotify(messageId: String, uid: String, message: VideoMessage) -> Bool {
        if ledger.contains(.video, uid: uid, id: messageId) {
            return false
        }

        if message.expiresAt < Date() {
            return false
        }

        // 새 메시지든 오프라인 캐치업이든 알린다. 재알림은 위의 계정별 ledger가 막는다.
        return message.createdAt != nil
    }

    private func catchUpChatNotifications(uid: String) {
        chatCatchUpTask?.cancel()
        chatCatchUpTask = Task { @MainActor in
            do {
                let counts = try await chatMessageService.unreadChatCounts()
                for (roomId, unread) in counts where unread > 0 {
                    if Task.isCancelled { return }
                    let messages = try await chatMessageService.roomChatMessages(roomId: roomId, limit: 20)
                    let newOnes = messages.filter { msg in
                        guard msg.senderUid != uid, let id = msg.id else { return false }
                        return !ledger.contains(.chat, uid: uid, id: id)
                    }
                    guard !newOnes.isEmpty else { continue }

                    for msg in newOnes {
                        if let id = msg.id { ledger.remember(.chat, uid: uid, id: id) }
                    }

                    let roomName = appState.rooms.first(where: { $0.id == roomId })?.name ?? "룸"
                    let latest = newOnes.max { lhs, rhs in
                        (lhs.createdAt ?? .distantPast) < (rhs.createdAt ?? .distantPast)
                    }
                    LocalNotificationCenter.shared.notifyChatCatchUp(
                        roomId: roomId,
                        roomName: roomName,
                        unreadCount: newOnes.count,
                        latestPreview: latest?.previewText ?? ""
                    )
                }
            } catch {
                NSLog("Chat catch-up failed: \(error)")
            }
        }
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

    // MARK: - 계정 전환

    private func setupAccountSwitching() {
        let center = NotificationCenter.default
        center.addObserver(forName: Notification.Name.pingSwitchAccount, object: nil, queue: .main) { [weak self] note in
            let userId = note.userInfo?[AccountIntentKey.userId] as? String
            Task { @MainActor in
                guard let self, let userId else { return }
                await self.handleSwitchAccount(userId: userId)
            }
        }
        center.addObserver(forName: Notification.Name.pingAddAccount, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in await self?.handleAddAccount() }
        }
        center.addObserver(forName: Notification.Name.pingRemoveAccount, object: nil, queue: .main) { [weak self] note in
            let userId = note.userInfo?[AccountIntentKey.userId] as? String
            Task { @MainActor in
                guard let self, let userId else { return }
                await self.handleRemoveAccount(userId: userId)
            }
        }
    }

    /// 전환/추가 전 공통 정리: 옵저버·창·캐시·상태·인메모리 dedup.
    private func teardownForAccountChange() {
        bootstrapTask?.cancel(); bootstrapTask = nil
        bootstrapRetryTask?.cancel(); bootstrapRetryTask = nil
        bootstrapFailureCount = 0
        roomObserverTask?.cancel(); roomObserverTask = nil
        invitationObserverTask?.cancel(); invitationObserverTask = nil
        incomingMessageTask?.cancel(); incomingMessageTask = nil
        cancelPlaybackPrefetches()
        chatCatchUpTask?.cancel(); chatCatchUpTask = nil
        stopDesktopPresenceHeartbeat()

        if mirrorWindow != nil { closeMirrorWindow() }
        roomManagerWindow?.close()
        roomManagerWindow = nil

        for window in playbackWindows { window.orderOut(nil) }
        playbackWindows.removeAll()
        playbackCache.removeAll()

        notifiedChatMessageIds.removeAll()

        appState.currentUser = nil
        appState.rooms = []
        appState.pendingInvitations = []
        appState.resetTransientState()
        appState.pendingRoomFocusId = nil
        appState.lastSelectedRoomId = nil
        appState.backendStatusMessage = nil
    }

    private func canSwitchAccountNow() -> Bool {
        if isSwitchingAccount { return false }
        if mirrorWindow != nil, mirrorViewModel.state != .idle {
            showTransientAlert(
                title: "전송 중에는 계정을 전환할 수 없습니다",
                message: "영상 전송을 마친 뒤 다시 시도해주세요."
            )
            return false
        }
        return true
    }

    private func reloadForActiveAccount() {
        // 호출자는 진입 전 canSwitchAccountNow()를 보장해야 한다.
        // switchTo는 isSwitchingAccount를 건드리지 않으므로 여기서의 재확인은 무해하다.
        guard canSwitchAccountNow() else { return }
        isSwitchingAccount = true
        teardownForAccountChange()
        Task { @MainActor in
            await chatRealtime.unsubscribeAll()
            await bootstrapBackend()
            isSwitchingAccount = false
        }
    }

    private func handleSwitchAccount(userId: String) async {
        guard canSwitchAccountNow() else { return }
        do {
            try SupabaseClient.shared.switchTo(userId: userId)
            reloadForActiveAccount()
        } catch {
            showTransientAlert(title: "계정 전환 실패", message: error.localizedDescription)
        }
    }

    private func handleAddAccount() async {
        guard canSwitchAccountNow() else { return }
        isSwitchingAccount = true
        do {
            let uid = try await SupabaseClient.shared.addAccount()
            teardownForAccountChange()
            await chatRealtime.unsubscribeAll()
            showOnboarding(uid: uid)
        } catch {
            showTransientAlert(title: "계정을 추가하지 못했습니다", message: error.localizedDescription)
        }
        isSwitchingAccount = false
    }

    private func handleRemoveAccount(userId: String) async {
        let wasActive = SupabaseClient.shared.activeUserId == userId
        // 활성 계정 삭제는 세션 교체 + 재로딩을 유발하므로 전송 중이면 막는다.
        // 비활성 계정 삭제는 세션/옵저버에 영향이 없어 그대로 진행한다.
        if wasActive, !canSwitchAccountNow() { return }
        SupabaseClient.shared.removeAccount(userId: userId)
        if wasActive {
            // 활성이 바뀌었으면(남은 계정 또는 0개) 재로딩. 0개면 bootstrap이 새 익명 계정을 만든다.
            reloadForActiveAccount()
        }
    }
}

extension AppDelegate: NSMenuDelegate {
    nonisolated func menuWillOpen(_ menu: NSMenu) {
        let signposter = OSSignposter(subsystem: "com.youngminpark.ping.Ping", category: "polling")
        signposter.emitEvent("menu-will-open")
    }
}

private extension ProcessInfo {
    var isRunningUnitTests: Bool {
        environment["XCTestConfigurationFilePath"] != nil
    }
}
