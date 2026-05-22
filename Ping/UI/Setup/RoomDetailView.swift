import AppKit
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
        _viewModel = StateObject(wrappedValue: HistoryViewModel(messageService: messageService, appState: appState))
    }

    private var currentRoom: Room? {
        appState.rooms.first(where: { $0.id == roomId })
    }

    var body: some View {
        VStack(spacing: 0) {
            // Room header
            if let room = currentRoom {
                HStack(spacing: 8) {
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
                        .padding(.horizontal, 4)
                    }

                    Button(action: { renameRoom(room) }) {
                        Label("이름 변경", systemImage: "pencil")
                            .labelStyle(.iconOnly)
                    }
                    .buttonStyle(.borderless)
                    .help("룸 이름 변경")
                    .padding(.horizontal, 4)

                    Button(action: { leaveRoom(room) }) {
                        Label("나가기", systemImage: "rectangle.portrait.and.arrow.right")
                            .labelStyle(.iconOnly)
                    }
                    .buttonStyle(.borderless)
                    .help("룸 나가기")
                    .padding(.horizontal, 4)
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

    private func renameRoom(_ room: Room) {
        let alert = NSAlert()
        alert.messageText = "룸 이름 변경"
        alert.informativeText = "새 룸 이름을 입력하세요."
        alert.addButton(withTitle: "변경")
        alert.addButton(withTitle: "취소")
        let input = NSTextField(string: room.name)
        input.frame = NSRect(x: 0, y: 0, width: 280, height: 24)
        alert.accessoryView = input
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        let newName = input.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !newName.isEmpty, newName != room.name else { return }
        Task { @MainActor in
            do {
                try await roomService?.renameRoom(roomId: roomId, newName: newName)
            } catch {
                NSLog("Rename failed: \(error)")
            }
        }
    }

    private func leaveRoom(_ room: Room) {
        guard let uid = appState.currentUser?.id else { return }
        let alert = NSAlert()
        alert.messageText = "룸 나가기"
        alert.informativeText = "'\(room.name)' 룸에서 나갑니다. 계속하시겠습니까?"
        alert.addButton(withTitle: "나가기")
        alert.addButton(withTitle: "취소")
        alert.buttons.first?.hasDestructiveAction = true
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        Task { @MainActor in
            do {
                try await roomService?.leaveRoom(roomId: roomId, uid: uid)
            } catch {
                NSLog("Leave failed: \(error)")
            }
        }
    }
}
