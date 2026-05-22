import SwiftUI

struct RoomDetailView: View {
    let roomId: String
    @ObservedObject var appState: AppState
    @ObservedObject var realtime: ChatRealtimeService
    let messageService: MessageService
    let cacheService: HistoryCacheService
    var onCopyInviteLink: ((Room) -> Void)?
    var roomService: RoomService?

    @StateObject private var viewModel: HistoryViewModel

    init(
        roomId: String,
        appState: AppState,
        realtime: ChatRealtimeService,
        messageService: MessageService,
        cacheService: HistoryCacheService,
        onCopyInviteLink: ((Room) -> Void)? = nil,
        roomService: RoomService? = nil
    ) {
        self.roomId = roomId
        self.appState = appState
        self.realtime = realtime
        self.messageService = messageService
        self.cacheService = cacheService
        self.onCopyInviteLink = onCopyInviteLink
        self.roomService = roomService
        _viewModel = StateObject(wrappedValue: HistoryViewModel(messageService: messageService))
    }

    private var currentRoom: Room? {
        appState.rooms.first(where: { $0.id == roomId })
    }

    var body: some View {
        VStack(spacing: 0) {
            // Room header
            if let room = currentRoom {
                HStack(spacing: 12) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(room.name)
                            .font(.headline)
                            .lineLimit(1)
                        Text("\(room.memberUids.count)명")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    Spacer()

                    if room.memberUids.count < RoomLimits.maxMembersPerRoom,
                       let onCopyInviteLink {
                        Button(action: { onCopyInviteLink(room) }) {
                            Label("초대링크 복사", systemImage: "link")
                                .labelStyle(.iconOnly)
                        }
                        .buttonStyle(.borderless)
                        .help("초대링크 복사")
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .background(Color(NSColor.windowBackgroundColor))

                Divider()
            }

            RoomTimelineView(viewModel: viewModel, cacheService: cacheService, appState: appState)
        }
        .onAppear {
            Task { await viewModel.selectRoom(roomId) }
        }
        .onChange(of: roomId) { newId in
            Task { await viewModel.selectRoom(newId) }
        }
        .onReceive(realtime.$lastEvent.compactMap { $0 }) { event in
            viewModel.handleRealtimeEvent(event)
        }
    }
}
