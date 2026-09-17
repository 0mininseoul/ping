import SwiftUI
import AppKit

struct HistoryView: View {
    @ObservedObject var appState: AppState
    @ObservedObject var viewModel: HistoryViewModel
    @ObservedObject var realtime: ChatRealtimeService
    let cacheService: HistoryCacheService

    @State private var keyMonitor: Any?
    @State private var expandedPlaybackWindow: ExpandedPlaybackWindow?
    @State private var screenFacePlaybackWindow: ScreenFacePlaybackWindow?

    var body: some View {
        HSplitView {
            HistorySidebar(rooms: appState.rooms, selectedRoomId: $viewModel.selectedRoomId)
                .frame(minWidth: 220, idealWidth: 240, maxWidth: 320)
                .onChange(of: viewModel.selectedRoomId) { newId in
                    guard let id = newId else { return }
                    Task { await viewModel.selectRoom(id) }
                }

            if viewModel.selectedRoomId != nil {
                RoomTimelineView(
                    viewModel: viewModel,
                    cacheService: cacheService,
                    appState: appState,
                    usesExternalScreenFaceExpansion: true,
                    onScreenFaceExpansionChange: { anchor, context in
                        handleScreenFaceExpansion(anchor: anchor, context: context)
                    }
                )
                    .frame(minWidth: 400)
            } else {
                VStack {
                    Text("좌측에서 룸을 선택하세요")
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
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
            dismissScreenFacePlayback()
        }
        .onReceive(realtime.$lastEvent.compactMap { $0 }) { event in
            viewModel.handleRealtimeEvent(event)
        }
        .onChange(of: viewModel.expandedMessageId) { newValue in
            guard let newValue else { return }
            guard let window = screenFacePlaybackWindow,
                  window.messageId != newValue else { return }
            dismissScreenFacePlayback()
        }
        .onChange(of: viewModel.selectedRoomId) { _ in
            dismissScreenFacePlayback()
            viewModel.expandedMessageId = nil
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
            return HistoryReplayRouting.dispatch(
                isFloatingPlaybackVisible: screenFacePlaybackWindow?.isVisible == true,
                replayFloating: { screenFacePlaybackWindow?.replay() },
                replayInline: { viewModel.inlineController.replay() }
            )
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

    private func handleScreenFaceExpansion(
        anchor: ScreenFaceExpansionAnchor?,
        context: ScreenFaceExpansionContext?
    ) {
        guard let context else {
            dismissScreenFacePlayback()
            return
        }

        presentScreenFacePlayback(context)
    }

    private func presentScreenFacePlayback(_ context: ScreenFaceExpansionContext) {
        let messageId = context.message.id ?? context.message.videoId
        if let window = screenFacePlaybackWindow {
            if window.messageId == messageId { // same message toggles closed
                dismissScreenFacePlayback()
                return
            }
            window.close()
            screenFacePlaybackWindow = nil
        }

        let parentWindow = NSApp.keyWindow ?? NSApp.mainWindow
        let window = ScreenFacePlaybackWindow(
            context: context,
            parentWindow: parentWindow,
            onDismiss: {
                if self.screenFacePlaybackWindow?.messageId == messageId {
                    self.screenFacePlaybackWindow = nil
                }
                if self.viewModel.expandedMessageId == messageId {
                    self.viewModel.expandedMessageId = nil
                }
            }
        )
        screenFacePlaybackWindow = window
        window.present()
    }

    private func dismissScreenFacePlayback() {
        guard let messageId = screenFacePlaybackWindow?.messageId else { return }
        screenFacePlaybackWindow?.close()
        screenFacePlaybackWindow = nil
        if viewModel.expandedMessageId == messageId {
            viewModel.expandedMessageId = nil
        }
    }
}

/// HistoryView's monitor is registered before the floating player's monitor,
/// so it must dispatch Return to the active floating player before consuming it.
enum HistoryReplayRouting {
    @MainActor
    @discardableResult
    static func dispatch(
        isFloatingPlaybackVisible: Bool,
        replayFloating: @MainActor () -> Void,
        replayInline: @MainActor () -> Void
    ) -> Bool {
        if isFloatingPlaybackVisible {
            replayFloating()
        } else {
            replayInline()
        }
        return true
    }
}
