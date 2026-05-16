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

struct RoomManagerView: View {
    @ObservedObject var appState: AppState
    var roomService: RoomService
    var invitationService: InvitationService
    var onJoinRoom: ((Room) -> Void)?
    var onInvite: (PingUser) -> Void

    @State private var selectedTab: RoomManagerTab = .rooms
    @StateObject private var searchViewModel: RoomSearchViewModel

    private enum RoomManagerTab: Hashable {
        case rooms
        case search
    }

    init(
        appState: AppState,
        roomService: RoomService,
        invitationService: InvitationService,
        onJoinRoom: ((Room) -> Void)? = nil,
        onInvite: @escaping (PingUser) -> Void
    ) {
        self.appState = appState
        self.roomService = roomService
        self.invitationService = invitationService
        self.onJoinRoom = onJoinRoom
        self.onInvite = onInvite
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
                    onRename: renameRoom
                )
            }
            .tabItem {
                Label("내 룸", systemImage: "person.2.fill")
            }
            .tag(RoomManagerTab.rooms)

            RoomSearchView(
                viewModel: searchViewModel,
                appState: appState,
                onJoinRoom: joinRoom,
                onInviteUser: onInvite
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
            } catch {
                appState.backendStatusMessage = error.localizedDescription
            }
        }
    }

    private func promptForRoomName(currentName: String) -> String? {
        let alert = NSAlert()
        alert.messageText = "룸 이름 변경"
        alert.informativeText = "새 룸 이름을 입력하세요."
        alert.addButton(withTitle: "변경")
        alert.addButton(withTitle: "취소")

        let input = NSTextField(string: currentName)
        input.frame = NSRect(x: 0, y: 0, width: 280, height: 24)
        alert.accessoryView = input

        let response = alert.runModal()
        guard response == .alertFirstButtonReturn else { return nil }
        return input.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
