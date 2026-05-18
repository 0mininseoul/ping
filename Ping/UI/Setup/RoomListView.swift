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
        HStack(spacing: 16) {
            Text("내 룸")
                .font(PingFont.title)

            Spacer()

            HStack(spacing: 10) {
                headerActionButton("룸 찾기", action: onFindRoom)

                headerActionButton("룸 만들기", isPrimary: true, action: onCreateRoom)
                    .disabled(!canCreateRoom)
            }
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
                headerActionButton("룸 만들기", isPrimary: true, action: onCreateRoom)
                    .disabled(!canCreateRoom)
                headerActionButton("룸 찾기", action: onFindRoom)
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
        HStack(alignment: .center, spacing: 18) {
            VStack(alignment: .leading, spacing: 11) {
                HStack(alignment: .firstTextBaseline, spacing: 10) {
                    Text(room.name)
                        .font(.system(size: 21, weight: .semibold))
                        .foregroundStyle(Color.primary.opacity(0.92))
                        .lineLimit(1)
                        .minimumScaleFactor(0.78)

                    statusBadge(for: room)
                        .fixedSize()
                }

                Text(partnerSummary(in: room))
                    .font(PingFont.body)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer(minLength: 14)

            roomActions(for: room)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 18)
        .frame(maxWidth: .infinity, minHeight: 112, alignment: .leading)
        .background {
            roomCardBackground
        }
    }

    private func headerActionButton(
        _ title: String,
        isPrimary: Bool = false,
        action: @escaping () -> Void
    ) -> some View {
        RoomHeaderActionButton(title: title, isPrimary: isPrimary, action: action)
    }

    private func roomActions(for room: Room) -> some View {
        HStack(spacing: 8) {
            if room.memberUids.count < RoomLimits.maxMembersPerRoom {
                iconAction(systemName: "link", accessibilityLabel: "초대링크 복사") {
                    onCopyInviteLink(room)
                }
            }

            Menu {
                Button("이름 변경") {
                    onRename(room)
                }

                Divider()

                Button("나가기", role: .destructive) {
                    leave(room)
                }
            } label: {
                iconLabel(systemName: "ellipsis", accessibilityLabel: "룸 메뉴")
            }
            .menuIndicator(.hidden)
            .buttonStyle(.plain)
            .fixedSize()
            .help("룸 메뉴")
        }
    }

    private func iconAction(
        systemName: String,
        accessibilityLabel: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            iconLabel(systemName: systemName, accessibilityLabel: accessibilityLabel)
        }
        .buttonStyle(.plain)
        .help(accessibilityLabel)
    }

    private func iconLabel(systemName: String, accessibilityLabel: String) -> some View {
        Image(systemName: systemName)
            .font(.system(size: 15, weight: .semibold))
            .foregroundStyle(Color.primary.opacity(0.82))
            .frame(width: 38, height: 38)
            .background {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(PingDesign.Surface.chipFill.opacity(0.94))
                    .overlay {
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .strokeBorder(PingDesign.Surface.strongHairline.opacity(0.64), lineWidth: 0.8)
                    }
            }
            .contentShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            .accessibilityLabel(accessibilityLabel)
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
        RoundedRectangle(cornerRadius: 24, style: .continuous)
            .fill(PingDesign.Surface.panelFill)
            .overlay {
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .strokeBorder(PingDesign.Surface.strongHairline.opacity(0.46), lineWidth: 0.8)
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

private struct RoomHeaderActionButton: View {
    @Environment(\.isEnabled) private var isEnabled
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var isHovering = false

    let title: String
    let isPrimary: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(PingFont.label)
                .foregroundStyle(textColor)
                .lineLimit(1)
                .minimumScaleFactor(0.86)
                .frame(width: 144, height: 46)
                .contentShape(Capsule(style: .continuous))
                .background {
                    background
                }
        }
        .buttonStyle(.plain)
        .scaleEffect(isInteractiveHovering ? 1.014 : 1)
        .offset(y: isInteractiveHovering ? -1 : 0)
        .animation(reduceMotion ? nil : PingDesign.Motion.buttonHover, value: isInteractiveHovering)
        .onHover { hovering in
            isHovering = hovering
        }
    }

    private var textColor: Color {
        if isPrimary {
            return Color.white.opacity(isEnabled ? 0.96 : 0.50)
        }
        return Color.primary.opacity(isEnabled ? 0.86 : 0.42)
    }

    private var isInteractiveHovering: Bool {
        isEnabled && isHovering
    }

    @ViewBuilder
    private var background: some View {
        if isPrimary {
            Capsule(style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [
                            PingDesign.ColorToken.accent.opacity(isEnabled ? 0.90 : 0.18),
                            PingDesign.ColorToken.accent.opacity(isEnabled ? 0.70 : 0.10)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .overlay {
                    Capsule(style: .continuous)
                        .fill(
                            LinearGradient(
                                colors: [
                                    Color.white.opacity(isEnabled ? 0.24 : 0.07),
                                    Color.clear
                                ],
                                startPoint: .top,
                                endPoint: .center
                            )
                        )
                }
                .overlay {
                    Capsule(style: .continuous)
                        .strokeBorder(
                            LinearGradient(
                                colors: [
                                    Color.white.opacity(isEnabled ? (isInteractiveHovering ? 0.58 : 0.52) : 0.14),
                                    Color.white.opacity(isEnabled ? 0.14 : 0.05)
                                ],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ),
                            lineWidth: 0.8
                        )
                }
                .pingShadow(isEnabled ? PingDesign.Shadow.accent : PingDesign.Shadow.none)
        } else {
            Capsule(style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [
                            PingDesign.Surface.chipFill.opacity(isEnabled ? (isInteractiveHovering ? 0.98 : 0.94) : 0.36),
                            PingDesign.Surface.panelFill.opacity(isEnabled ? 0.90 : 0.28)
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                .overlay {
                    Capsule(style: .continuous)
                        .strokeBorder(
                            LinearGradient(
                                colors: [
                                    PingDesign.Surface.strongHairline.opacity(isEnabled ? (isInteractiveHovering ? 0.82 : 0.70) : 0.18),
                                    Color.primary.opacity(isEnabled ? 0.08 : 0.03)
                                ],
                                startPoint: .top,
                                endPoint: .bottom
                            ),
                            lineWidth: 0.8
                        )
                }
                .pingShadow(isEnabled ? PingDesign.Shadow.control : PingDesign.Shadow.none)
        }
    }
}
