import AppKit
import SwiftUI

@MainActor
final class RoomManagerWindow: NSWindow {
    init<Content: View>(rootView: Content) {
        super.init(
            contentRect: NSRect(x: 0, y: 0, width: 600, height: 700),
            styleMask: [.titled, .closable, .resizable],
            backing: .buffered,
            defer: false
        )

        title = "내 룸"
        minSize = NSSize(width: 600, height: 700)
        contentView = NSHostingView(rootView: rootView)
        isReleasedWhenClosed = false
        center()
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

    @State private var selectedTab: RoomManagerTab
    @StateObject private var searchViewModel: RoomSearchViewModel
    private let searchInitialTab: RoomSearchTab

    init(
        appState: AppState,
        roomService: RoomService,
        invitationService: InvitationService,
        initialTab: RoomManagerTab = .rooms,
        searchInitialTab: RoomSearchTab = .rooms,
        onJoinRoom: ((Room) -> Void)? = nil,
        onCopyInviteLink: @escaping (Room) -> Void = { _ in },
        onJoinInviteLink: @escaping (String) -> Void = { _ in },
        onInvite: @escaping (PingUser) -> Void
    ) {
        self.appState = appState
        self.roomService = roomService
        self.invitationService = invitationService
        self.onJoinRoom = onJoinRoom
        self.onCopyInviteLink = onCopyInviteLink
        self.onJoinInviteLink = onJoinInviteLink
        self.onInvite = onInvite
        self.searchInitialTab = searchInitialTab
        _selectedTab = State(initialValue: initialTab)
        _searchViewModel = StateObject(
            wrappedValue: RoomSearchViewModel(excludingUid: appState.currentUser?.id)
        )
    }

    var body: some View {
        TabView(selection: $selectedTab) {
            VStack(spacing: 0) {
                if !appState.pendingInvitations.isEmpty {
                    invitationsStrip
                }

                RoomListView(
                    appState: appState,
                    roomService: roomService,
                    onRename: renameRoom,
                    onCopyInviteLink: onCopyInviteLink,
                    onCreateRoom: createRoom,
                    onFindRoom: { selectedTab = .search }
                )
            }
            .tabItem {
                Label("내 룸", systemImage: "person.2.fill")
            }
            .tag(RoomManagerTab.rooms)

            RoomSearchView(
                viewModel: searchViewModel,
                appState: appState,
                initialTab: searchInitialTab,
                onJoinRoom: joinRoom,
                onInviteUser: onInvite,
                onJoinInviteLink: onJoinInviteLink
            )
            .tabItem {
                Label("룸 찾기", systemImage: "magnifyingglass")
            }
            .tag(RoomManagerTab.search)
        }
        .frame(minWidth: 600, minHeight: 700)
    }

    private var invitationsStrip: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("받은 초대")
                .font(PingFont.label)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 20)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 12) {
                    ForEach(appState.pendingInvitations) { invitation in
                        InvitationCard(
                            invitation: invitation,
                            onAccept: { acceptInvitation(invitation) },
                            onReject: { rejectInvitation(invitation) }
                        )
                        .frame(width: 270)
                    }
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 4)
            }
        }
        .padding(.top, 16)
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
                selectedTab = .rooms
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
                selectedTab = .rooms
            } catch {
                appState.backendStatusMessage = error.localizedDescription
            }
        }
    }

    private func renameRoom(_ room: Room) {
        guard room.ownerUid == appState.currentUser?.id,
              let roomId = room.id,
              let newName = promptForRoomName(currentName: room.name),
              !newName.isEmpty,
              newName != room.name else {
            return
        }

        Task { @MainActor in
            do {
                try await roomService.renameRoom(roomId: roomId, newName: newName)
                renameLocalRoom(roomId: roomId, newName: newName)
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

        sortRooms()
    }

    private func renameLocalRoom(roomId: String, newName: String) {
        guard let index = appState.rooms.firstIndex(where: { $0.id == roomId }) else {
            return
        }

        appState.rooms[index].name = newName
        appState.rooms[index].searchableName = SearchableText.normalize(newName)
        sortRooms()
    }

    private func sortRooms() {
        appState.rooms.sort { lhs, rhs in
            lhs.name.localizedStandardCompare(rhs.name) == .orderedAscending
        }
    }

    private func promptForRoomName(currentName: String) -> String? {
        let alert = NSAlert()
        alert.messageText = currentName.isEmpty ? "룸 만들기" : "룸 이름 변경"
        alert.informativeText = currentName.isEmpty ? "새 룸 이름을 입력하세요." : "새 룸 이름을 입력하세요."
        alert.addButton(withTitle: currentName.isEmpty ? "만들기" : "변경")
        alert.addButton(withTitle: "취소")

        let input = NSTextField(string: currentName)
        input.frame = NSRect(x: 0, y: 0, width: 280, height: 24)
        alert.accessoryView = input

        let response = alert.runModal()
        guard response == .alertFirstButtonReturn else { return nil }
        return input.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
