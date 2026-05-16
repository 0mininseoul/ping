import SwiftUI

struct RoomListView: View {
    @ObservedObject var appState: AppState
    var roomService: RoomService
    var onLeave: ((Room) -> Void)?
    var onRename: (Room) -> Void

    init(
        appState: AppState,
        roomService: RoomService,
        onLeave: ((Room) -> Void)? = nil,
        onRename: @escaping (Room) -> Void = { _ in }
    ) {
        self.appState = appState
        self.roomService = roomService
        self.onLeave = onLeave
        self.onRename = onRename
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
                LazyVGrid(columns: columns, spacing: 14) {
                    ForEach(appState.rooms) { room in
                        roomCard(room)
                    }
                }
                .padding(20)
            }
        }
    }

    private var emptyState: some View {
        GlassPanel {
            VStack(spacing: 12) {
                Image(systemName: "person.2.slash")
                    .font(.system(size: 32, weight: .semibold))
                    .foregroundStyle(.secondary)
                Text("아직 룸이 없습니다")
                    .font(PingFont.title)
                Text("룸 찾기에서 열린 룸에 참여하거나 사용자를 초대하세요.")
                    .font(PingFont.body)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            .frame(maxWidth: .infinity)
            .padding(28)
        }
    }

    private func roomCard(_ room: Room) -> some View {
        GlassPanel {
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

                    if isOwner(room) {
                        Spacer()
                        GlassButton("이름 변경") {
                            onRename(room)
                        }
                    }
                }
            }
            .padding(14)
        }
    }

    private func statusBadge(for room: Room) -> some View {
        Text(room.status == .full ? "활성" : "대기")
            .font(PingFont.caption)
            .foregroundStyle(room.status == .full ? Color.green : Color.yellow)
            .lineLimit(1)
            .padding(.horizontal, 9)
            .padding(.vertical, 5)
            .background {
                Capsule()
                    .glassEffect()
                    .overlay {
                        Capsule()
                            .strokeBorder(
                                (room.status == .full ? Color.green : Color.yellow).opacity(0.45),
                                lineWidth: 1
                            )
                    }
            }
    }

    private func partnerSummary(in room: Room) -> String {
        guard let myUid = appState.currentUser?.id else {
            return "사용자 정보를 불러오는 중"
        }

        if room.status == .open || room.memberUids.count < 2 {
            return "상대 참여 대기 중"
        }

        return room.memberNicknames.first(where: { $0.key != myUid })?.value ?? "알 수 없는 파트너"
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
