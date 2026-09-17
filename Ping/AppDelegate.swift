import AppKit
import Combine
import Network
import OSLog
import SwiftUI
import UserNotifications

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem?
    private var mirrorWindow: MirrorWindow?
    private var onboardingWindow: OnboardingWindow?
    private var roomManagerWindow: RoomManagerWindow?
    private var settingsWindow: SettingsWindow?
    private var playbackWindows: [PlaybackWindow] = []
    private lazy var playbackVideoCache = PlaybackVideoCache { [weak self] message in
        guard let self else { throw PingError.supabaseUnavailable }
        return try await self.downloadMessageVideo(message)
    }

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
    private let presenceStore = PresenceStore.shared
    private let appStartTime = Date()
    private let ledger = NotificationLedger()
    private lazy var autoFaceReply = AutoFaceReplyCoordinator(
        camera: camera,
        messageService: messageService,
        appStartedAt: appStartTime,
        isMirrorUsingCamera: { [weak self] in self?.mirrorWindow != nil }
    )

    private var notifiedChatMessageIds: Set<String> = []
    private var deliveringVideoIds: Set<String> = []
    private var pendingAutoReplyBatches: [String: AutoReplyBatch] = [:]
    private var isSwitchingAccount = false
    private var cancellables: Set<AnyCancellable> = []

    private var roomObserverTask: Task<Void, Never>?
    private var invitationObserverTask: Task<Void, Never>?
    private var incomingMessageTask: Task<Void, Never>?
    private var chatCatchUpTask: Task<Void, Never>?
    private var incomingVideoPokeTask: Task<Void, Never>?
    private var desktopPresenceTask: Task<Void, Never>?
    private var bootstrapTask: Task<Void, Never>?
    private var bootstrapRetryTask: Task<Void, Never>?
    private var bootstrapFailureCount = 0
    private var networkMonitor: NWPathMonitor?
    private var cameraStartTask: Task<Void, Never>?
    private var pendingInviteToken: String?
    private var currentMirrorMode: CaptureMode?
    private let isAgentManagedProcess = PingLaunchOrigin.isAgentManaged()

    private var showsOnboardingForQA: Bool {
        #if DEBUG
        ProcessInfo.processInfo.arguments.contains("--show-onboarding")
        #else
        false
        #endif
    }

    func applicationWillFinishLaunching(_ notification: Notification) {
        if !ProcessInfo.processInfo.isRunningUnitTests {
            switch singleInstanceAction() {
            case .proceed:
                break
            case .yield:
                exit(0)
            case .replaceExisting(let pids):
                replaceDuplicateInstances(pids)
            }
        }

        enforceAccessoryActivationPolicy()
    }

    /// 마지막 폴백. 정상 경로에서는 전임자가 `handOffToLaunchdInstance`로 **스스로**
    /// 물러나므로 여기까지 오지 않는다. 샌드박스 때문에 이 경로의 quit 요청은 전달되지
    /// 않을 수 있고, 그래서 여기에만 의존하면 0.3.75처럼 중복이 남는다.
    ///
    /// 소유권 이전은 시작만 여기서 하고, 확인과 강제는 런치 밖으로 내보낸다.
    ///
    /// `applicationWillFinishLaunching`은 런루프가 뜨기 전 메인 스레드다. 여기서 전임자가
    /// 죽기를 기다리면 그 시간만큼 우리 런치가 통째로 멈춘다. 기다릴 이유도 없다 —
    /// 살아남는 쪽은 우리고, 전임자는 자기 속도로 종료하면 된다.
    private func replaceDuplicateInstances(_ pids: [pid_t]) {
        for pid in pids {
            NSRunningApplication(processIdentifier: pid)?.terminate()
        }

        DispatchQueue.global(qos: .utility).async {
            let forced = DuplicateInstanceTerminator.replace(
                pids: pids,
                politeQuit: { NSRunningApplication(processIdentifier: $0)?.terminate() },
                // `NSRunningApplication(processIdentifier:)`가 nil이면 "종료됨"으로 읽혔는데,
                // 조회 실패와 실제 종료를 구분하지 못한다. 그렇게 오판하면 강제 폴백이
                // 건너뛰어지고 로그조차 남지 않는다. 커널에 직접 묻는다.
                hasExited: { pid in
                    if kill(pid, 0) == 0 { return false }
                    return errno == ESRCH
                },
                forceQuit: { NSRunningApplication(processIdentifier: $0)?.forceTerminate() },
                waitStep: { Thread.sleep(forTimeInterval: 0.25) },
                maxChecks: 8
            )
            guard !forced.isEmpty else { return }
            // 정중한 요청이 끝내 안 먹힌 경우다. 추론 말고 기록으로 남긴다 —
            // 강제까지 갔는데 그마저 실패하면 중복이 살아남고, 그 사실을 알 길이 없다.
            Logger(subsystem: "com.youngminpark.ping.Ping", category: "autostart")
                .error("force-terminated duplicate instances: \(forced.map(String.init).joined(separator: ","), privacy: .public)")
        }
    }

    private func singleInstanceAction() -> SingleInstanceAction {
        guard let bundleIdentifier = Bundle.main.bundleIdentifier else { return .proceed }

        return SingleInstanceGuard.action(
            runningPIDs: SingleInstanceGuard.runningPIDs(forBundleIdentifier: bundleIdentifier),
            currentPID: ProcessInfo.processInfo.processIdentifier,
            isAgentManaged: isAgentManagedProcess
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
            Task { @MainActor in
                await AutoStartController.shared.applyPolicyAtLaunch(
                    isAgentManaged: isAgentManagedProcess
                )
            }

            if showsOnboardingForQA {
                showOnboardingPreviewForQA()
                return
            }

            UpdaterController.shared.start()
            startNetworkRecoveryMonitor()
            startBootstrapTaskIfNeeded()
        }
    }

    func applicationDidBecomeActive(_ notification: Notification) {
        enforceAccessoryActivationPolicySoon()
    }

    func application(
        _ application: NSApplication,
        didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data
    ) {
        RemotePushRegistrar.shared.update(deviceToken: deviceToken)
    }

    func application(
        _ application: NSApplication,
        didFailToRegisterForRemoteNotificationsWithError error: Error
    ) {
        RemotePushRegistrar.shared.recordRegistrationFailure(error)
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
        incomingVideoPokeTask?.cancel()
        desktopPresenceTask?.cancel()
        networkMonitor?.cancel()
        networkMonitor = nil
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

        if !ProcessInfo.processInfo.isRunningUnitTests {
            Task { @MainActor in
                await RemotePushRegistrar.shared.registerForRemoteNotificationsIfAuthorized()
            }
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

    /// Auto-start launches Ping at login, often before Wi-Fi has associated and
    /// DNS is answering. The first bootstrap then fails with a network error and,
    /// without this, nothing ever tries again until the user quits and relaunches.
    /// Watching reachability turns that into a self-healing wait.
    private func startNetworkRecoveryMonitor() {
        guard networkMonitor == nil else { return }

        let monitor = NWPathMonitor()
        monitor.pathUpdateHandler = { [weak self] path in
            guard path.status == .satisfied else { return }
            Task { @MainActor in
                guard let self else { return }
                if let uid = self.appState.currentUser?.id {
                    await RemotePushRegistrar.shared.registerForRemoteNotificationsIfAuthorized()
                    await RemotePushRegistrar.shared.registerIfPossible(uid: uid)
                } else {
                    self.startBootstrapTaskIfNeeded()
                }
            }
        }
        monitor.start(queue: DispatchQueue(label: "com.youngminpark.ping.network-recovery"))
        networkMonitor = monitor
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
                await recoverNotificationPermissionIfNeeded()
                await RemotePushRegistrar.shared.registerForRemoteNotificationsIfAuthorized()
                await RemotePushRegistrar.shared.registerIfPossible(uid: uid)
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

    /// 온보딩은 계정이 이미 있으면 아예 뜨지 않는다. 그 경로로 들어온 맥은 알림 권한을
    /// 한 번도 물어본 적이 없어 macOS 알림 레지스트리에 등록조차 안 되고, 시스템 설정 ›
    /// 알림 목록에서 앱이 통째로 사라져 사용자가 되돌릴 방법이 없다. 여기서 한 번 요청해
    /// 등록을 만든다. 이미 결정한 상태(허용/거부)는 건드리지 않는다.
    private func recoverNotificationPermissionIfNeeded() async {
        let status = await UNUserNotificationCenter.current().notificationSettings().authorizationStatus
        guard NotificationPermissionRecovery.shouldRequestAuthorization(for: status) else { return }

        let granted = await LocalNotificationCenter.shared.requestAuthorization()
        ClientEventService.shared.log(
            "notification_permission_recovered",
            properties: ["granted": granted]
        )
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

                // 룸 폴링은 10초마다 같은 목록을 다시 흘려보낸다. 이미 붙어 있으면
                // 세션 토큰 조회조차 하지 않는다.
                let roomIds = rooms.compactMap(\.id)
                if chatRealtime.needsSubscription(roomIds: roomIds) {
                    Task { @MainActor in
                        if let url = try? SupabaseClient.shared.configURL,
                           let anonKey = try? SupabaseClient.shared.configAnonKey {
                            let token = await SupabaseClient.shared.currentAccessToken()
                            await self.chatRealtime.subscribe(
                                roomIds: roomIds,
                                uid: uid,
                                supabaseURL: url,
                                anonKey: anonKey,
                                accessToken: token
                            )
                        }
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
                await deliverIncomingVideo(message, uid: uid)
            }
        }
    }

    /// Realtime이 붙어 있으면 도착 즉시, 아니면 10초 폴링이 이 경로로 들어온다.
    /// 두 경로가 같은 메시지를 동시에 물 수 있으므로 진행 중 id를 따로 막는다 —
    /// ledger 기록은 알림을 await 한 뒤라 그것만으로는 겹침을 못 막는다.
    private func deliverIncomingVideo(_ message: VideoMessage, uid: String) async {
        guard let id = message.id, shouldNotify(messageId: id, uid: uid, message: message) else {
            return
        }
        guard !deliveringVideoIds.contains(id) else { return }
        deliveringVideoIds.insert(id)
        defer { deliveringVideoIds.remove(id) }

        // 알림 권한이 없어도 자동 회신은 동작해야 하므로 아래 조기 반환보다 먼저 건다.
        // 녹화·업로드를 여기서 기다리면 그동안 알림이 밀리므로 별도 task로 넘긴다.
        Task { @MainActor [weak self] in
            guard let self else { return }
            await self.autoFaceReply.handleIncoming(message, currentUser: self.appState.currentUser)
        }

        let didScheduleNotification = await LocalNotificationCenter.shared.notifyIncomingMessage(
            senderNickname: message.senderNickname,
            messageId: id,
            roomId: message.roomId
        )
        guard didScheduleNotification else { return }
        ledger.remember(.video, uid: uid, id: id)
        try? await messageService.markNotified(messageId: id)

        // 다운로드를 여기서 기다리면 느린 한 건이 뒤따르는 모든 알림을 지연시키므로
        // 재생 준비는 별도 task로 넘긴다.
        let shouldAutoPlay = PingAutoPlayPreference.shouldAutoPlay(
            messageCreatedAt: message.createdAt,
            appStartedAt: appStartTime
        )
        Task { @MainActor [weak self] in
            guard let self else { return }
            guard let localURL = await self.playbackVideoCache.prefetch(message) else { return }
            guard shouldAutoPlay else { return }
            // 한 핑에 여러 명이 답한다. 준비되는 대로 띄우면 같은 좌표에 하나씩 포개진다.
            if message.isAutoReply {
                self.enqueueAutoReply(message, localURL: localURL)
            } else {
                self.presentPlaybacks([Playback(message: message, localURL: localURL)], isAutoPlay: true)
            }
        }
    }

    /// Realtime INSERT 신호를 받으면 폴링 주기를 기다리지 않고 곧바로 읽어 온다.
    private func fetchIncomingVideosNow() {
        guard let uid = appState.currentUser?.id else { return }
        incomingVideoPokeTask?.cancel()
        incomingVideoPokeTask = Task { @MainActor [weak self] in
            guard let self else { return }
            do {
                for message in try await self.messageService.incomingMessages() {
                    if Task.isCancelled { return }
                    await self.deliverIncomingVideo(message, uid: uid)
                }
            } catch {
                NSLog("Realtime incoming video fetch failed: \(error)")
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

    /// 메뉴를 여는 순간 직전 스냅샷으로 먼저 채우고, 응답이 오면 다시 채운다.
    /// 상시 폴링을 하지 않으므로 첫 줄이 잠깐 이전 상태일 수 있다.
    @MainActor
    private func refreshStatusMenuPresence() async {
        applyStatusMenuPresence()
        await presenceStore.refresh(roomIds: appState.rooms.compactMap(\.id))
        applyStatusMenuPresence()
    }

    @MainActor
    private func applyStatusMenuPresence() {
        guard let item = statusItem?.menu?.item(withTag: StatusMenuBuilder.presenceItemTag) else { return }

        let rooms = appState.rooms
        let names = DesktopPresencePolicy.liveMemberNames(
            memberUids: rooms.flatMap(\.memberUids),
            excluding: appState.currentUser?.id,
            presence: presenceStore.members,
            nicknameForUid: { uid in
                rooms.compactMap { $0.memberNicknames[uid] }.first ?? "(알 수 없음)"
            }
        )

        item.title = StatusMenuBuilder.presenceTitle(names: names)
    }

    private var visibleRoomIdForPresence: String? {
        RoomFocusPolicy.activeRoomIdForPresence(
            appIsActive: NSApp.isActive,
            roomWindowIsVisible: roomManagerWindow?.isVisible ?? false,
            lastSelectedRoomId: appState.lastSelectedRoomId
        )
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

    /// - Parameter isAutoPlay: 계측용 구분. 두 경로 모두 앱을 앞으로 가져온다 —
    ///   포커스를 넘기지 않으면 로컬 키 감시가 죽어 Esc로 창을 지울 수 없다.
    private func playMessage(messageId: String, isAutoPlay: Bool = false) {
        Task { @MainActor in
            ForegroundPresenter.activateApp()
            do {
                guard let message = try await messageService.get(messageId: messageId) else { return }
                let localURL = try await playbackVideoCache.url(for: message)
                presentPlaybacks([Playback(message: message, localURL: localURL)], isAutoPlay: isAutoPlay)
            } catch {
                NSLog("Playback failed: \(error)")
            }
        }
    }

    /// 한 묶음을 통째로 받아 배치를 먼저 정하고, 창은 전부 만든 뒤 같이 띄운다.
    /// 창을 하나씩 만들어 띄우면 자동 회신처럼 좌표가 같은 묶음이 한 점에 포개진다.
    private func presentPlaybacks(_ items: [Playback], isAutoPlay: Bool) {
        let items = items.filter { $0.message.id != nil }
        guard !items.isEmpty else { return }

        ForegroundPresenter.activateApp()

        let screen = NSScreen.main ?? NSScreen.screens.first!
        let visibleFrame = screen.visibleFrame
        let sizes = items.map {
            PlaybackWindow.size(for: $0.message.captureMode, aspectRatio: $0.message.aspectRatio, on: screen)
        }
        // 묶음의 중심은 원본 핑이 찍힌 자리다. 회신은 전부 그 좌표를 물고 온다.
        let center = ScreenCoordinates.denormalize(position: items[0].message.mirrorPosition, in: visibleFrame)
        let origins = PlaybackGroupLayout.origins(sizes: sizes, centeredAt: center, inSafeArea: visibleFrame)

        var opened: [PlaybackWindow] = []
        for (index, item) in items.enumerated() {
            let message = item.message
            let localURL = item.localURL
            guard let messageId = message.id else { continue }
            let shouldKeepReceivedVideo = LocalArchive.saveReceivedEnabled && message.allowsLocalSave

            let windowId = UUID()
            let window = PlaybackWindow(
                videoURL: localURL,
                mode: message.captureMode,
                aspectRatio: message.aspectRatio,
                atScreenPoint: origins[index],
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
                            self?.playbackVideoCache.discard(messageId: messageId)
                        }
                        self?.playbackWindows.removeAll { $0.pingWindowId == windowId }
                    }
                }
            )
            window.pingWindowId = windowId
            playbackWindows.append(window)
            opened.append(window)
            ClientEventService.shared.log("ping_received_view", properties: [
                "mode": message.captureMode.rawValue,
                "auto": isAutoPlay,
                "group_size": items.count
            ])
        }

        for window in opened { window.fadeIn() }
    }

    /// 자동 회신은 룸 단위로 모았다가 한 번에 띄운다. 준비되는 대로 하나씩 띄우면
    /// 같은 좌표에 포개져 한 명씩 순서대로 뜨는 것처럼 보인다.
    private func enqueueAutoReply(_ message: VideoMessage, localURL: URL) {
        let roomId = message.roomId
        var batch = pendingAutoReplyBatches[roomId] ?? AutoReplyBatch(firstArrivedAt: Date())
        batch.items.append(Playback(message: message, localURL: localURL))
        batch.flushTask?.cancel()
        batch.flushTask = nil

        let expected = expectedAutoReplyCount(roomId: roomId)
        switch AutoReplyBatchPolicy.decide(
            collected: batch.items.count,
            expected: expected,
            firstArrivedAt: batch.firstArrivedAt
        ) {
        case .present:
            pendingAutoReplyBatches[roomId] = nil
            presentAutoReplyBatch(batch, roomId: roomId, expected: expected, timedOut: false)
        case .waitUntil(let deadline):
            batch.flushTask = Task { @MainActor [weak self] in
                try? await Task.sleep(for: .seconds(max(0, deadline.timeIntervalSinceNow)))
                guard !Task.isCancelled else { return }
                self?.flushAutoReplyBatch(roomId: roomId)
            }
            pendingAutoReplyBatches[roomId] = batch
        }
    }

    private func flushAutoReplyBatch(roomId: String) {
        guard let batch = pendingAutoReplyBatches.removeValue(forKey: roomId) else { return }
        batch.flushTask?.cancel()
        presentAutoReplyBatch(
            batch,
            roomId: roomId,
            expected: expectedAutoReplyCount(roomId: roomId),
            timedOut: true
        )
    }

    /// "회신이 하나만 떴다"는 신고를 추론이 아니라 조회로 답하기 위해 모인 수와 기대치를 남긴다.
    private func presentAutoReplyBatch(_ batch: AutoReplyBatch, roomId: String, expected: Int, timedOut: Bool) {
        guard !batch.items.isEmpty else { return }
        ClientEventService.shared.log("auto_reply_batch_presented", properties: [
            "room_id": roomId,
            "collected": batch.items.count,
            "expected": expected,
            "timed_out": timedOut
        ])
        presentPlaybacks(batch.items, isAutoPlay: true)
    }

    /// 이 룸에서 회신이 올 수 있는 최대 인원. 룸 목록을 아직 못 받았으면 0을 돌려
    /// 첫 회신에서 바로 띄운다 — 모르는 채로 기다리면 1:1에서도 수집 창만큼 늦게 뜬다.
    private func expectedAutoReplyCount(roomId: String) -> Int {
        guard let myUid = appState.currentUser?.id,
              let room = appState.rooms.first(where: { $0.id == roomId }) else { return 0 }
        return room.memberUids.filter { $0 != myUid }.count
    }

    private func cancelPendingAutoReplyBatches() {
        for batch in pendingAutoReplyBatches.values { batch.flushTask?.cancel() }
        pendingAutoReplyBatches.removeAll()
    }

    private func cancelPlaybackPrefetches() {
        playbackVideoCache.cancelAll()
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
                    await RemotePushRegistrar.shared.registerForRemoteNotificationsIfAuthorized()
                    await RemotePushRegistrar.shared.registerIfPossible(uid: uid)

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
        if case .incomingVideo = event {
            fetchIncomingVideosNow()
            return
        }
        guard case .chatInserted(let msg) = event else { return }
        guard msg.senderUid != appState.currentUser?.id else { return }
        guard let id = msg.id, !notifiedChatMessageIds.contains(id) else { return }
        notifiedChatMessageIds.insert(id)
        if notifiedChatMessageIds.count > 500 {
            notifiedChatMessageIds = Set(notifiedChatMessageIds.suffix(500))
        }

        // 지금 그 룸을 보고 있으면 알리지 않는다. 창이 떠 있다는 것만으로는 부족하다 —
        // 가려진 창도 isVisible이 true라 알림이 조용히 사라졌다.
        let isViewingRoom = RoomFocusPolicy.isViewingRoom(
            roomId: msg.roomId,
            appIsActive: NSApp.isActive,
            roomWindowIsVisible: roomManagerWindow?.isVisible ?? false,
            pendingRoomFocusId: appState.pendingRoomFocusId,
            lastSelectedRoomId: appState.lastSelectedRoomId
        )

        // 이 결정은 원격에서 볼 수 없어 여러 차례 오진했다. 판단 근거를 함께 남긴다.
        ClientEventService.shared.log("chat_notify_decision", properties: [
            "suppressed": isViewingRoom,
            "app_active": NSApp.isActive,
            "window_visible": roomManagerWindow?.isVisible ?? false,
            "room_id": msg.roomId
        ])

        if isViewingRoom { return }

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

        cancelPendingAutoReplyBatches()
        for window in playbackWindows { window.orderOut(nil) }
        playbackWindows.removeAll()
        playbackVideoCache.reset()

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

        Task { @MainActor [weak self] in
            await self?.refreshStatusMenuPresence()
        }
    }
}

private extension ProcessInfo {
    var isRunningUnitTests: Bool {
        environment["XCTestConfigurationFilePath"] != nil
    }
}

/// 재생 준비가 끝난 한 건. 묶음으로 배치를 계산하려면 창을 만들기 전에 전부 손에 있어야 한다.
struct Playback {
    let message: VideoMessage
    let localURL: URL
}

/// 한 핑에 달린 자동 회신을 모으는 통. 마감은 첫 회신 시각에 고정한다.
struct AutoReplyBatch {
    let firstArrivedAt: Date
    var items: [Playback] = []
    var flushTask: Task<Void, Never>?
}
