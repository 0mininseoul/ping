import SwiftUI

struct RoomListView: View {
    @ObservedObject var appState: AppState
    var roomService: RoomService
    var onLeave: ((Room) -> Void)?
    var onRename: (Room) -> Void
    var onCopyInviteLink: (Room) -> Void
    var onCreateRoom: () -> Void
    var onFindRoom: () -> Void

    init(
        appState: AppState,
        roomService: RoomService,
        onLeave: ((Room) -> Void)? = nil,
        onRename: @escaping (Room) -> Void = { _ in },
        onCopyInviteLink: @escaping (Room) -> Void = { _ in },
        onCreateRoom: @escaping () -> Void = {},
        onFindRoom: @escaping () -> Void = {}
    ) {
        self.appState = appState
        self.roomService = roomService
        self.onLeave = onLeave
        self.onRename = onRename
        self.onCopyInviteLink = onCopyInviteLink
        self.onCreateRoom = onCreateRoom
        self.onFindRoom = onFindRoom
    }

    private let columns = [
        GridItem(.flexible(), spacing: 14),
        GridItem(.flexible(), spacing: 14)
    ]

    var body: some View {
        ScrollView {
            if appState.rooms.isEmpty {
                emptyState
                    .padding(24)
            } else {
                VStack(alignment: .leading, spacing: 14) {
                    roomCountHeader

                    LazyVGrid(columns: columns, spacing: 14) {
                        ForEach(appState.rooms) { room in
                            roomCard(room)
                        }
                    }
                }
                .padding(20)
            }
        }
    }

    private var roomCountHeader: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text("내 룸")
                    .font(PingFont.title)

                Text("\(appState.rooms.count)/\(RoomLimits.maxRoomsPerUser)개 사용 중")
                    .font(PingFont.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            GlassButton("룸 찾기", action: onFindRoom)

            GlassButton("룸 만들기", isPrimary: true, action: onCreateRoom)
                .disabled(!canCreateRoom)
        }
        .padding(.horizontal, 2)
    }

    private var emptyState: some View {
        VStack(spacing: 16) {
            Image(systemName: "person.2.slash")
                .font(.system(size: 34, weight: .semibold))
                .foregroundStyle(.secondary)

            VStack(spacing: 7) {
                Text("아직 룸이 없습니다")
                    .font(PingFont.title)
                Text("새 룸을 만들거나 열린 룸에 참여하세요.")
                    .font(PingFont.body)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }

            HStack(spacing: 10) {
                GlassButton("룸 만들기", isPrimary: true, action: onCreateRoom)
                    .disabled(!canCreateRoom)
                GlassButton("룸 찾기", action: onFindRoom)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(34)
        .background {
            RoundedRectangle(cornerRadius: 26, style: .continuous)
                .fill(PingDesign.Surface.rowFill)
                .overlay {
                    RoundedRectangle(cornerRadius: 26, style: .continuous)
                        .strokeBorder(PingDesign.Surface.strongHairline.opacity(0.52), lineWidth: 0.8)
                }
        }
        .pingShadow(PingDesign.Shadow.panel)
    }

    private func roomCard(_ room: Room) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top, spacing: 8) {
                VStack(alignment: .leading, spacing: 6) {
                    Text(room.name)
                        .font(PingFont.title)
                        .lineLimit(2)
                        .minimumScaleFactor(0.82)

                    Text(partnerSummary(in: room))
                        .font(PingFont.body)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }

                Spacer(minLength: 6)

                statusBadge(for: room)
            }

            Divider()
                .opacity(0.35)

            HStack(spacing: 8) {
                GlassButton("나가기") {
                    leave(room)
                }

                Spacer()

                if room.memberUids.count < RoomLimits.maxMembersPerRoom {
                    GlassButton("링크 복사") {
                        onCopyInviteLink(room)
                    }
                }

                if isOwner(room) {
                    GlassButton("이름 변경") {
                        onRename(room)
                    }
                }
            }
        }
        .padding(14)
        .background {
            roomCardBackground
        }
    }

    private func statusBadge(for room: Room) -> some View {
        let isFull = room.memberUids.count >= RoomLimits.maxMembersPerRoom
        let isActive = room.memberUids.count >= RoomLimits.minSendableMembers
        let color = isActive ? PingDesign.ColorToken.success : PingDesign.ColorToken.warning

        return Text(isFull ? "가득 참" : (isActive ? "활성" : "대기"))
            .font(PingFont.caption)
            .foregroundStyle(color)
            .lineLimit(1)
            .padding(.horizontal, 9)
            .padding(.vertical, 5)
            .background {
                Capsule()
                    .fill(color.opacity(0.12))
                    .overlay {
                        Capsule()
                            .strokeBorder(color.opacity(0.36), lineWidth: 1)
                    }
            }
    }

    private var roomCardBackground: some View {
        RoundedRectangle(cornerRadius: 22, style: .continuous)
            .fill(PingDesign.Surface.panelFill)
            .overlay {
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .strokeBorder(PingDesign.Surface.strongHairline.opacity(0.50), lineWidth: 0.8)
            }
            .pingShadow(PingDesign.Shadow.panel)
    }

    private func partnerSummary(in room: Room) -> String {
        guard let myUid = appState.currentUser?.id else {
            return "사용자 정보를 불러오는 중"
        }

        if room.memberUids.count < RoomLimits.minSendableMembers {
            return "상대 참여 대기 중"
        }

        let others = room.memberUids
            .filter { $0 != myUid }
            .compactMap { room.memberNicknames[$0] }

        if others.isEmpty {
            return "알 수 없는 파트너"
        }

        if others.count <= 2 {
            return others.joined(separator: ", ")
        }

        return "\(others[0]), \(others[1]) 외 \(others.count - 2)명"
    }

    private var canCreateRoom: Bool {
        appState.rooms.count < RoomLimits.maxRoomsPerUser
    }

    private func isOwner(_ room: Room) -> Bool {
        room.ownerUid == appState.currentUser?.id
    }

    private func leave(_ room: Room) {
        if let onLeave {
            onLeave(room)
            return
        }

        guard let roomId = room.id,
              let uid = appState.currentUser?.id else {
            return
        }

        Task { @MainActor in
            do {
                try await roomService.leaveRoom(roomId: roomId, uid: uid)
            } catch {
                appState.backendStatusMessage = error.localizedDescription
            }
        }
    }
}
