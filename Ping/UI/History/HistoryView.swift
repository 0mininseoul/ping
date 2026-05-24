import SwiftUI
import AppKit

struct HistoryView: View {
    @ObservedObject var appState: AppState
    @ObservedObject var viewModel: HistoryViewModel
    @ObservedObject var realtime: ChatRealtimeService
    let cacheService: HistoryCacheService

    @State private var keyMonitor: Any?
    @State private var expandedPlaybackWindow: ExpandedPlaybackWindow?
    private var expandedScreenFaceMessage: VideoMessage? {
        guard let expandedMessageId = viewModel.expandedMessageId else { return nil }
        for group in viewModel.groups {
            for item in group.items {
                if case .video(let message) = item {
                    if message.id == expandedMessageId && message.captureMode == .screenFace {
                        return message
                    }
                }
            }
        }
        return nil
    }

    var body: some View {
        HSplitView {
            HistorySidebar(rooms: appState.rooms, selectedRoomId: $viewModel.selectedRoomId)
                .frame(minWidth: 220, idealWidth: 240, maxWidth: 320)
                .onChange(of: viewModel.selectedRoomId) { newId in
                    guard let id = newId else { return }
                    Task { await viewModel.selectRoom(id) }
                }

            if viewModel.selectedRoomId != nil {
                RoomTimelineView(viewModel: viewModel, cacheService: cacheService, appState: appState)
                    .frame(minWidth: 400)
            } else {
                VStack {
                    Text("좌측에서 룸을 선택하세요")
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .overlayPreferenceValue(ExpandedScreenFaceVideoAnchorKey.self) { anchors in
            screenFaceExpansionOverlay(anchors)
        }
        .onAppear {
            keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
                handleKey(event) ? nil : event
            }
        }
        .onDisappear {
            if let keyMonitor {
                NSEvent.removeMonitor(keyMonitor)
                self.keyMonitor = nil
            }
        }
        .onReceive(realtime.$lastEvent.compactMap { $0 }) { event in
            viewModel.handleRealtimeEvent(event)
        }
    }

    private func handleKey(_ event: NSEvent) -> Bool {
        // If a text input (TextEditor/NSTextView) has focus, don't intercept any keys.
        if let responder = NSApp.keyWindow?.firstResponder,
           responder.isKind(of: NSTextView.self) {
            return false
        }
        let allItems = viewModel.groups.flatMap(\.items)
        let videoOnlyIds: [String] = allItems.compactMap { item in
            if case .video(let v) = item { return v.id } else { return nil }
        }
        let expandedIdx = viewModel.expandedMessageId.flatMap { id in
            videoOnlyIds.firstIndex(of: id)
        }

        switch event.keyCode {
        case 126: // up
            if let i = expandedIdx, i > 0 {
                viewModel.expandedMessageId = videoOnlyIds[i - 1]
            } else if expandedIdx == nil, let first = videoOnlyIds.first {
                viewModel.expandedMessageId = first
            }
            return true
        case 125: // down
            if let i = expandedIdx, i + 1 < videoOnlyIds.count {
                viewModel.expandedMessageId = videoOnlyIds[i + 1]
            } else if expandedIdx == nil, let first = videoOnlyIds.first {
                viewModel.expandedMessageId = first
            }
            return true
        case 36: // Enter: replay (only when video expanded and not in composer)
            // composer's Cmd+Enter is handled by RoomTimelineView's monitor before us
            guard !event.modifierFlags.contains(.command) else { return false }
            viewModel.inlineController.replay()
            return true
        case 49: // Space: expand
            if let player = viewModel.inlineController.player,
               let id = viewModel.expandedMessageId {
                let video = allItems.compactMap { item -> VideoMessage? in
                    if case .video(let v) = item, v.id == id { return v }
                    return nil
                }.first
                if let video, let screen = NSApp.keyWindow?.screen {
                    let aspect: Double = video.captureMode == .screenFace ? (video.aspectRatio ?? 1.78) : 1.0
                    let expanded = ExpandedPlaybackWindow(
                        player: player,
                        aspectRatio: aspect,
                        on: screen,
                        onDismiss: {
                            self.expandedPlaybackWindow?.orderOut(nil)
                            self.expandedPlaybackWindow = nil
                        }
                    )
                    expandedPlaybackWindow = expanded
                    expanded.present()
                }
            }
            return true
        case 53: // Esc
            if viewModel.expandedMessageId != nil {
                viewModel.expandedMessageId = nil
            } else if viewModel.replyTarget != nil {
                viewModel.replyTarget = nil
            } else {
                NSApp.keyWindow?.close()
            }
            return true
        default:
            return false
        }
    }

    @ViewBuilder
    private func screenFaceExpansionOverlay(_ anchors: [String: Anchor<CGRect>]) -> some View {
        GeometryReader { proxy in
            if let message = expandedScreenFaceMessage,
               let id = message.id,
               let anchor = anchors[id] {
                let rect = proxy[anchor]
                let size = InlinePlayerView.playerSize(for: message)
                let myUid = appState.currentUser?.id
                let isMine = message.senderUid == myUid

                InlinePlayerView(
                    message: message,
                    isMine: isMine,
                    archivePeerName: archivePeerName(for: message, isMine: isMine, myUid: myUid),
                    cacheService: cacheService,
                    controller: viewModel.inlineController
                )
                .frame(width: size.width, height: size.height)
                .position(
                    x: screenFaceOverlayX(anchorRect: rect, size: size, containerWidth: proxy.size.width),
                    y: rect.midY
                )
                .allowsHitTesting(false)
                .zIndex(10)
            }
        }
    }

    private func screenFaceOverlayX(anchorRect: CGRect, size: CGSize, containerWidth: CGFloat) -> CGFloat {
        let trailingEdge = min(containerWidth - 16, anchorRect.maxX)
        let proposed = trailingEdge - size.width / 2
        let minCenter = min(size.width / 2 + 16, containerWidth / 2)
        let maxCenter = max(containerWidth - size.width / 2 - 16, containerWidth / 2)
        return min(max(proposed, minCenter), maxCenter)
    }

    private func archivePeerName(for message: VideoMessage, isMine: Bool, myUid: String?) -> String {
        guard isMine else { return message.senderNickname }
        guard let room = appState.rooms.first(where: { $0.id == message.roomId }) else {
            return message.senderNickname
        }

        let otherNames = room.memberUids
            .filter { $0 != myUid }
            .compactMap { room.memberNicknames[$0] }
        if otherNames.count == 1 {
            return otherNames[0]
        }

        return room.name
    }
}
