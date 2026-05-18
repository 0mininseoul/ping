import Combine
import Foundation
import SwiftUI

@MainActor
final class RoomSearchViewModel: ObservableObject {
    @Published var query = ""
    @Published private(set) var roomResults: [Room] = []
    @Published private(set) var userResults: [PingUser] = []
    @Published private(set) var isSearching = false
    @Published var errorMessage: String?

    private let roomService: RoomService
    private let userService: UserService
    private var excludingUid: String?
    private var cancellables = Set<AnyCancellable>()
    private var searchTask: Task<Void, Never>?

    init(excludingUid: String?) {
        self.excludingUid = excludingUid
        self.roomService = RoomService()
        self.userService = UserService()
        configureDebouncedSearch()
    }

    init(excludingUid: String?, roomService: RoomService, userService: UserService) {
        self.excludingUid = excludingUid
        self.roomService = roomService
        self.userService = userService
        configureDebouncedSearch()
    }

    private func configureDebouncedSearch() {
        $query
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .removeDuplicates()
            .debounce(for: .milliseconds(300), scheduler: RunLoop.main)
            .sink { [weak self] prefix in
                Task { @MainActor in
                    self?.scheduleSearch(prefix: prefix)
                }
            }
            .store(in: &cancellables)
    }

    func updateExcludingUid(_ uid: String?) {
        excludingUid = uid
    }

    func searchNow() {
        scheduleSearch(prefix: query.trimmingCharacters(in: .whitespacesAndNewlines))
    }

    private func scheduleSearch(prefix: String) {
        searchTask?.cancel()

        guard !prefix.isEmpty else {
            roomResults = []
            userResults = []
            isSearching = false
            errorMessage = nil
            return
        }

        searchTask = Task { [weak self] in
            await self?.runSearch(prefix: prefix)
        }
    }

    private func runSearch(prefix: String) async {
        isSearching = true
        errorMessage = nil

        do {
            let rooms = try await roomService.searchOpenRooms(prefix: prefix)
            guard !Task.isCancelled else { return }

            let users = try await userService.searchByNicknamePrefix(prefix, excluding: excludingUid)
            guard !Task.isCancelled else { return }

            roomResults = rooms
            userResults = users
            isSearching = false
        } catch {
            guard !Task.isCancelled else { return }
            roomResults = []
            userResults = []
            isSearching = false
            errorMessage = error.localizedDescription
        }
    }
}

enum RoomSearchTab: Hashable {
    case rooms
    case users
}

struct RoomSearchView: View {
    @ObservedObject var viewModel: RoomSearchViewModel
    @ObservedObject var appState: AppState
    var onJoinRoom: (Room) -> Void
    var onInviteUser: (PingUser) -> Void
    var onJoinInviteLink: (String) -> Void

    @State private var selectedTab: RoomSearchTab
    @State private var inviteLinkText = ""
    @FocusState private var searchFocused: Bool

    init(
        viewModel: RoomSearchViewModel,
        appState: AppState,
        initialTab: RoomSearchTab = .rooms,
        onJoinRoom: @escaping (Room) -> Void,
        onInviteUser: @escaping (PingUser) -> Void,
        onJoinInviteLink: @escaping (String) -> Void
    ) {
        self.viewModel = viewModel
        self.appState = appState
        self.onJoinRoom = onJoinRoom
        self.onInviteUser = onInviteUser
        self.onJoinInviteLink = onJoinInviteLink
        _selectedTab = State(initialValue: initialTab)
    }

    var body: some View {
        VStack(spacing: 14) {
            searchField
            inviteLinkJoinField
            tabPicker

            if let error = viewModel.errorMessage {
                Text(error)
                    .font(PingFont.caption)
                    .foregroundStyle(Color.yellow)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            results
        }
        .padding(20)
        .onAppear {
            viewModel.updateExcludingUid(appState.currentUser?.id)
            searchFocused = true
        }
    }

    private var inviteLinkJoinField: some View {
        HStack(spacing: 10) {
            Image(systemName: "link")
                .foregroundStyle(.secondary)
            TextField("초대 링크 또는 코드", text: $inviteLinkText)
                .textFieldStyle(.plain)
                .font(PingFont.body)
                .onSubmit(joinInviteLink)

            GlassButton("초대 링크로 참여", isPrimary: PingInviteLink.token(from: inviteLinkText) != nil) {
                joinInviteLink()
            }
            .disabled(PingInviteLink.token(from: inviteLinkText) == nil)
            .opacity(PingInviteLink.token(from: inviteLinkText) == nil ? 0.55 : 1)
        }
        .padding(12)
        .background {
            searchSurface(isFocused: false)
        }
    }

    private func joinInviteLink() {
        guard let token = PingInviteLink.token(from: inviteLinkText) else {
            viewModel.errorMessage = "초대 링크나 초대 코드를 확인해 주세요."
            return
        }

        viewModel.errorMessage = nil
        onJoinInviteLink(token)
    }

    private var searchField: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)
            TextField("룸 이름 또는 닉네임 검색", text: $viewModel.query)
                .textFieldStyle(.plain)
                .font(PingFont.body)
                .focused($searchFocused)
                .onSubmit { viewModel.searchNow() }
            if viewModel.isSearching {
                ProgressView()
                    .controlSize(.small)
            }
        }
        .padding(12)
        .background {
            searchSurface(isFocused: searchFocused)
        }
    }

    private var tabPicker: some View {
        Picker("", selection: $selectedTab) {
            Text("룸 \(viewModel.roomResults.count)")
                .tag(RoomSearchTab.rooms)
            Text("사용자 \(viewModel.userResults.count)")
                .tag(RoomSearchTab.users)
        }
        .pickerStyle(.segmented)
    }

    @ViewBuilder private var results: some View {
        ScrollView {
            LazyVStack(spacing: 10) {
                switch selectedTab {
                case .rooms:
                    if viewModel.roomResults.isEmpty {
                        emptyResults("열린 룸이 없습니다")
                    } else {
                        ForEach(viewModel.roomResults) { room in
                            roomResult(room)
                        }
                    }
                case .users:
                    if viewModel.userResults.isEmpty {
                        emptyResults("검색된 사용자가 없습니다")
                    } else {
                        ForEach(viewModel.userResults) { user in
                            userResult(user)
                        }
                    }
                }
            }
            .padding(.vertical, 4)
        }
    }

    private func roomResult(_ room: Room) -> some View {
        let alreadyJoined = isCurrentUserMember(of: room)

        return HStack(spacing: 12) {
            Image(systemName: "person.2.fill")
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(.secondary)
                .frame(width: 28)

            VStack(alignment: .leading, spacing: 4) {
                Text(room.name)
                    .font(PingFont.body)
                    .lineLimit(1)
                Text("방장: \(ownerName(for: room))")
                    .font(PingFont.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer()

            GlassButton(alreadyJoined ? "내 룸" : "참여 요청", isPrimary: !alreadyJoined) {
                guard !alreadyJoined else { return }
                onJoinRoom(room)
            }
            .disabled(alreadyJoined)
            .opacity(alreadyJoined ? 0.55 : 1)
        }
        .padding(12)
        .background {
            resultSurface
        }
    }

    private func userResult(_ user: PingUser) -> some View {
        let sharesExistingRoom = sharesRoom(with: user)

        return HStack(spacing: 12) {
            Image(systemName: "person.crop.circle.fill")
                .font(.system(size: 20, weight: .semibold))
                .foregroundStyle(.secondary)
                .frame(width: 28)

            VStack(alignment: .leading, spacing: 4) {
                Text(user.nickname)
                    .font(PingFont.body)
                    .lineLimit(1)
                Text(user.rooms.isEmpty ? "참여 중인 룸 없음" : "룸 \(user.rooms.count)개")
                    .font(PingFont.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            GlassButton(sharesExistingRoom ? "내 룸" : "초대", isPrimary: !sharesExistingRoom) {
                guard !sharesExistingRoom else { return }
                onInviteUser(user)
            }
            .disabled(sharesExistingRoom || user.id == nil)
            .opacity(sharesExistingRoom || user.id == nil ? 0.55 : 1)
        }
        .padding(12)
        .background {
            resultSurface
        }
    }

    private func emptyResults(_ message: String) -> some View {
        VStack(spacing: 8) {
            Image(systemName: "tray")
                .font(.system(size: 24, weight: .medium))
                .foregroundStyle(.secondary)
            Text(viewModel.query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "검색어를 입력하세요" : message)
                .font(PingFont.body)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 42)
    }

    private func isCurrentUserMember(of room: Room) -> Bool {
        guard let uid = appState.currentUser?.id else { return false }
        return room.memberUids.contains(uid)
    }

    private func sharesRoom(with user: PingUser) -> Bool {
        let myRoomIds = Set(appState.rooms.compactMap(\.id))
        return user.rooms.contains { myRoomIds.contains($0) }
    }

    private func ownerName(for room: Room) -> String {
        room.memberNicknames[room.ownerUid] ?? "알 수 없음"
    }

    private func searchSurface(isFocused: Bool) -> some View {
        RoundedRectangle(cornerRadius: 22, style: .continuous)
            .fill(isFocused ? PingDesign.Surface.inputFieldFocusedFill : PingDesign.Surface.inputFieldFill)
            .overlay {
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .strokeBorder(
                        isFocused
                            ? PingDesign.ColorToken.accent.opacity(0.45)
                            : PingDesign.Surface.strongHairline.opacity(0.50),
                        lineWidth: isFocused ? 1.1 : 0.8
                    )
            }
            .pingShadow(PingDesign.Shadow.control)
    }

    private var resultSurface: some View {
        RoundedRectangle(cornerRadius: 18, style: .continuous)
            .fill(PingDesign.Surface.panelFill)
            .overlay {
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .strokeBorder(PingDesign.Surface.strongHairline.opacity(0.45), lineWidth: 0.8)
            }
            .pingShadow(PingDesign.Shadow.panel)
    }
}
