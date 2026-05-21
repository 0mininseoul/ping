import AppKit
import SwiftUI

struct HistoryView: View {
    @ObservedObject var appState: AppState
    @ObservedObject var viewModel: HistoryViewModel
    let cacheService: HistoryCacheService

    @State private var keyMonitor: Any?

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
    }

    private func handleKey(_ event: NSEvent) -> Bool {
        let allMsgs = viewModel.groups.flatMap(\.messages)
        let current = viewModel.expandedMessageId.flatMap { id in
            allMsgs.firstIndex(where: { $0.id == id })
        }

        switch event.keyCode {
        case 126: // up
            if let i = current, i > 0 {
                viewModel.expandedMessageId = allMsgs[i - 1].id
            } else if current == nil, let first = allMsgs.first {
                viewModel.expandedMessageId = first.id
            }
            return true
        case 125: // down
            if let i = current, i + 1 < allMsgs.count {
                viewModel.expandedMessageId = allMsgs[i + 1].id
            } else if current == nil, let first = allMsgs.first {
                viewModel.expandedMessageId = first.id
            }
            return true
        case 53: // Esc
            if viewModel.expandedMessageId != nil {
                viewModel.expandedMessageId = nil
            } else {
                NSApp.keyWindow?.close()
            }
            return true
        default:
            return false
        }
    }
}
