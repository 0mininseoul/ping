import AppKit
import SwiftUI

@MainActor
final class RoomManagerWindow: NSWindow {
    private let titlebarActionHandler = RoomManagerTitlebarActionHandler()
    private let titlebarActionController = NSTitlebarAccessoryViewController()
    private var isSuppressingDefaultToolbar = false

    override var toolbar: NSToolbar? {
        didSet {
            guard toolbar != nil, !isSuppressingDefaultToolbar else { return }
            isSuppressingDefaultToolbar = true
            DispatchQueue.main.async { [weak self] in
                self?.toolbar = nil
                self?.isSuppressingDefaultToolbar = false
            }
        }
    }

    init<Content: View>(rootView: Content) {
        super.init(
            contentRect: NSRect(x: 0, y: 0, width: 500, height: 592),
            styleMask: [.titled, .closable, .resizable],
            backing: .buffered,
            defer: false
        )

        title = "내 룸"
        minSize = NSSize(width: 480, height: 560)
        contentView = NSHostingView(rootView: rootView)
        isReleasedWhenClosed = false
        installTitlebarActions()
        suppressDefaultSidebarToolbar()
        center()
    }

    private func installTitlebarActions() {
        titlebarActionController.layoutAttribute = .right
        titlebarActionController.view = RoomManagerTitlebarActionHandler.makeAccessoryView(
            target: titlebarActionHandler
        )
        addTitlebarAccessoryViewController(titlebarActionController)
    }

    private func suppressDefaultSidebarToolbar() {
        let delays: [TimeInterval] = [0, 0.05, 0.25, 1.0]
        for delay in delays {
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
                self?.toolbar = nil
            }
        }
    }
}

private enum RoomManagerToolbarNotification {
    static let createRoom = Notification.Name("PingRoomManagerCreateRoomRequested")
    static let searchRoom = Notification.Name("PingRoomManagerSearchRoomRequested")
}

@MainActor
private final class RoomManagerTitlebarActionHandler: NSObject {
    static func makeAccessoryView(target: RoomManagerTitlebarActionHandler) -> NSView {
        let stackView = NSStackView()
        stackView.orientation = .horizontal
        stackView.alignment = .centerY
        stackView.spacing = 12
        stackView.translatesAutoresizingMaskIntoConstraints = false

        let buttons: [NSButton] = [
            iconButton(
                label: "새 룸 만들기",
                symbolName: "plus",
                target: target,
                action: #selector(createRoom(_:))
            ),
            iconButton(
                label: "룸 찾기",
                symbolName: "magnifyingglass",
                target: target,
                action: #selector(searchRoom(_:))
            ),
            iconButton(
                label: "사이드바",
                symbolName: "sidebar.left",
                target: target,
                action: #selector(toggleSidebar(_:))
            )
        ]
        buttons.forEach(stackView.addArrangedSubview)

        let container = NSView(frame: NSRect(x: 0, y: 0, width: 124, height: 32))
        container.addSubview(stackView)
        NSLayoutConstraint.activate([
            stackView.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            stackView.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            stackView.centerYAnchor.constraint(equalTo: container.centerYAnchor)
        ])
        return container
    }

    private static func iconButton(
        label: String,
        symbolName: String,
        target: AnyObject,
        action: Selector
    ) -> NSButton {
        let image = NSImage(systemSymbolName: symbolName, accessibilityDescription: label)
        let button = NSButton(title: "", image: image ?? NSImage(), target: target, action: action)
        button.bezelStyle = .texturedRounded
        button.isBordered = false
        button.imageScaling = .scaleProportionallyDown
        button.contentTintColor = .secondaryLabelColor
        button.toolTip = label
        button.setAccessibilityLabel(label)
        button.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            button.widthAnchor.constraint(equalToConstant: 28),
            button.heightAnchor.constraint(equalToConstant: 28)
        ])
        return button
    }

    @objc private func toggleSidebar(_ sender: Any?) {
        NSApp.sendAction(#selector(NSSplitViewController.toggleSidebar(_:)), to: nil, from: sender)
    }

    @objc private func createRoom(_ sender: Any?) {
        NotificationCenter.default.post(name: RoomManagerToolbarNotification.createRoom, object: nil)
    }

    @objc private func searchRoom(_ sender: Any?) {
        NotificationCenter.default.post(name: RoomManagerToolbarNotification.searchRoom, object: nil)
    }
}

enum RoomManagerTab: Hashable {
    case rooms
    case search
}

struct RoomManagerView: View {
    @ObservedObject var appState: AppState
    var roomService: RoomService
    var invitationService: InvitationService
    var onJoinRoom: ((Room) -> Void)?
    var onCopyInviteLink: (Room) -> Void
    var onJoinInviteLink: (String) -> Void
    var onInvite: (PingUser) -> Void

    // Injected services for RoomDetailView
    var chatRealtime: ChatRealtimeService?
    var messageService: MessageService?
    var cacheService: HistoryCacheService?

    @State private var selectedRoomId: String?
    @State private var isSearchPresented: Bool = false
    @State private var screenFaceExpansionAnchor: ScreenFaceExpansionAnchor?
    @State private var screenFaceExpansionContext: ScreenFaceExpansionContext?

    @StateObject private var searchViewModel: RoomSearchViewModel
    private let searchInitialTab: RoomSearchTab
    private let opensSearchOnAppear: Bool

    init(
        appState: AppState,
        roomService: RoomService,
        invitationService: InvitationService,
        initialTab: RoomManagerTab = .rooms,
        searchInitialTab: RoomSearchTab = .rooms,
        chatRealtime: ChatRealtimeService? = nil,
        messageService: MessageService? = nil,
        cacheService: HistoryCacheService? = nil,
        onJoinRoom: ((Room) -> Void)? = nil,
        onCopyInviteLink: @escaping (Room) -> Void = { _ in },
        onJoinInviteLink: @escaping (String) -> Void = { _ in },
        onInvite: @escaping (PingUser) -> Void
    ) {
        self.appState = appState
        self.roomService = roomService
        self.invitationService = invitationService
        self.chatRealtime = chatRealtime
        self.messageService = messageService
        self.cacheService = cacheService
        self.onJoinRoom = onJoinRoom
        self.onCopyInviteLink = onCopyInviteLink
        self.onJoinInviteLink = onJoinInviteLink
        self.onInvite = onInvite
        self.searchInitialTab = searchInitialTab
        self.opensSearchOnAppear = (initialTab == .search)
        _searchViewModel = StateObject(
            wrappedValue: RoomSearchViewModel(excludingUid: appState.currentUser?.id)
        )
    }

    var body: some View {
        NavigationSplitView {
            sidebarContent
                .frame(minWidth: 148, idealWidth: sidebarWidth, maxWidth: 240)
                .navigationSplitViewColumnWidth(min: 148, ideal: sidebarWidth, max: 240)
        } detail: {
            detailContent
        }
        .removingDefaultSidebarToggle()
        .toolbar(.hidden, for: .windowToolbar)
        .frame(minWidth: 480, minHeight: 560)
        .overlay {
            ScreenFaceExpansionOverlay(
                anchor: screenFaceExpansionAnchor,
                context: screenFaceExpansionContext
            )
        }
        .sheet(isPresented: $isSearchPresented) {
            VStack(spacing: 0) {
                HStack {
                    Button(action: { isSearchPresented = false }) {
                        Circle()
                            .fill(Color(red: 1.0, green: 0.36, blue: 0.36))
                            .frame(width: 12, height: 12)
                    }
                    .buttonStyle(.plain)
                    .keyboardShortcut(.escape, modifiers: [])
                    .help("닫기")

                    Spacer()
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
                .background(.regularMaterial)

                RoomSearchView(
                    viewModel: searchViewModel,
                    appState: appState,
                    initialTab: searchInitialTab,
                    onJoinRoom: joinRoom,
                    onInviteUser: onInvite,
                    onJoinInviteLink: onJoinInviteLink
                )
            }
            .frame(minWidth: 700, minHeight: 600)
        }
        .onAppear {
            selectInitialRoomIfNeeded()
            if opensSearchOnAppear {
                isSearchPresented = true
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: RoomManagerToolbarNotification.createRoom)) { _ in
            createRoom()
        }
        .onReceive(NotificationCenter.default.publisher(for: RoomManagerToolbarNotification.searchRoom)) { _ in
            isSearchPresented = true
        }
        .onChange(of: appState.rooms.map(\.id)) { _ in
            selectInitialRoomIfNeeded()
        }
        .onChange(of: appState.pendingRoomFocusId) { roomId in
            guard let roomId else { return }
            selectedRoomId = roomId
            appState.pendingRoomFocusId = nil
        }
        .onChange(of: selectedRoomId) { newValue in
            appState.lastSelectedRoomId = newValue
            if let newValue {
                LocalNotificationCenter.shared.clearDeliveredNotifications(roomId: newValue)
            }
            updateScreenFaceExpansion(anchor: nil, context: nil)
        }
    }

    private var sidebarWidth: CGFloat {
        let longestNameLength = appState.rooms
            .map { RoomLimits.sanitizedRoomName($0.name).count }
            .max() ?? 0
        let measuredWidth = 132 + CGFloat(longestNameLength) * 7
        return min(240, max(156, measuredWidth))
    }

    @ViewBuilder
    private var sidebarContent: some View {
        List(selection: $selectedRoomId) {
            if !appState.pendingInvitations.isEmpty {
                Section("받은 초대") {
                    ForEach(appState.pendingInvitations) { invitation in
                        InvitationCard(
                            invitation: invitation,
                            onAccept: { acceptInvitation(invitation) },
                            onReject: { rejectInvitation(invitation) }
                        )
                        .padding(.vertical, 2)
                        // Not selectable — use a nil tag so it doesn't affect selectedRoomId
                        .tag(Optional<String>.none)
                    }
                }
            }

            Section("내 룸") {
                if appState.rooms.isEmpty {
                    Text("룸이 없습니다")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .padding(.vertical, 4)
                } else {
                    ForEach(appState.rooms, id: \.id) { room in
                        VStack(alignment: .leading, spacing: 2) {
                            Text(RoomLimits.sanitizedRoomName(room.name))
                                .font(.callout.weight(.semibold))
                                .lineLimit(1)
                                .truncationMode(.tail)
                            Text("\(room.memberUids.count)명")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                        .padding(.vertical, 4)
                        .tag(room.id)
                    }
                }
            }
        }
        .listStyle(.sidebar)
    }

    @ViewBuilder
    private var detailContent: some View {
        if let roomId = selectedRoomId,
           let realtime = chatRealtime,
           let msgService = messageService,
           let cache = cacheService {
            RoomDetailView(
                roomId: roomId,
                appState: appState,
                realtime: realtime,
                messageService: msgService,
                cacheService: cache,
                onCopyInviteLink: onCopyInviteLink,
                roomService: roomService,
                usesExternalScreenFaceExpansion: true,
                onScreenFaceExpansionChange: { anchor, context in
                    updateScreenFaceExpansion(anchor: anchor, context: context)
                }
            )
        } else {
            VStack(spacing: 12) {
                Image(systemName: "person.2")
                    .font(.system(size: 48))
                    .foregroundStyle(.tertiary)
                Text("좌측에서 룸을 선택하세요")
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private func selectInitialRoomIfNeeded() {
        if let selectedRoomId,
           appState.rooms.contains(where: { $0.id == selectedRoomId }) {
            return
        }

        let persistedId = appState.lastSelectedRoomId
        if let persistedId,
           appState.rooms.contains(where: { $0.id == persistedId }) {
            selectedRoomId = persistedId
            return
        }

        selectedRoomId = appState.defaultRoom?.id ?? appState.rooms.first?.id
    }

    private func updateScreenFaceExpansion(
        anchor: ScreenFaceExpansionAnchor?,
        context: ScreenFaceExpansionContext?
    ) {
        screenFaceExpansionAnchor = anchor
        screenFaceExpansionContext = context
    }

    private func joinRoom(_ room: Room) {
        if let onJoinRoom {
            onJoinRoom(room)
            return
        }

        guard let roomId = room.id,
              let currentUser = appState.currentUser,
              let uid = currentUser.id else {
            return
        }

        Task { @MainActor in
            do {
                try await roomService.joinRoom(roomId: roomId, uid: uid, nickname: currentUser.nickname)
                isSearchPresented = false
            } catch {
                appState.backendStatusMessage = error.localizedDescription
            }
        }
    }

    private func acceptInvitation(_ invitation: Invitation) {
        guard let currentUser = appState.currentUser,
              let uid = currentUser.id else {
            return
        }

        Task { @MainActor in
            do {
                try await invitationService.accept(
                    invitation: invitation,
                    myUid: uid,
                    myNickname: currentUser.nickname,
                    roomService: roomService
                )
            } catch {
                appState.backendStatusMessage = error.localizedDescription
            }
        }
    }

    private func rejectInvitation(_ invitation: Invitation) {
        guard let inviteId = invitation.id else { return }

        Task { @MainActor in
            do {
                try await invitationService.reject(inviteId: inviteId)
            } catch {
                appState.backendStatusMessage = error.localizedDescription
            }
        }
    }

    private func createRoom() {
        guard let currentUser = appState.currentUser,
              let uid = currentUser.id,
              appState.rooms.count < RoomLimits.maxRoomsPerUser,
              let roomName = promptForRoomName(currentName: ""),
              !roomName.isEmpty else {
            return
        }

        Task { @MainActor in
            do {
                let createdRoom = try await roomService.createRoom(
                    name: roomName,
                    ownerUid: uid,
                    ownerNickname: currentUser.nickname
                )
                insertOrReplaceRoom(createdRoom)
                UserDefaults.standard.set(false, forKey: PingPreferenceKeys.roomSetupDeferred)
                selectedRoomId = createdRoom.id
            } catch {
                appState.backendStatusMessage = error.localizedDescription
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

    private func promptForRoomName(currentName: String) -> String? {
        let alert = NSAlert()
        alert.messageText = "룸 만들기"
        alert.informativeText = "새 룸 이름을 입력하세요. 최대 \(RoomLimits.maxRoomNameLength)자까지 사용할 수 있습니다."
        alert.addButton(withTitle: "만들기")
        alert.addButton(withTitle: "취소")

        let input = NSTextField(string: currentName)
        input.frame = NSRect(x: 0, y: 0, width: 280, height: 24)
        alert.accessoryView = input

        let response = alert.runModal()
        guard response == .alertFirstButtonReturn else { return nil }
        return RoomLimits.sanitizedRoomName(input.stringValue)
    }
}

private extension View {
    @ViewBuilder
    func removingDefaultSidebarToggle() -> some View {
        if #available(macOS 14.0, *) {
            toolbar(removing: .sidebarToggle)
        } else {
            self
        }
    }
}
