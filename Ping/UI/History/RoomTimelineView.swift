import SwiftUI
import AppKit

struct RoomTimelineView: View {
    @ObservedObject var viewModel: HistoryViewModel
    let cacheService: HistoryCacheService
    @ObservedObject var appState: AppState

    @State private var draft: String = ""
    @State private var reactionPickerTargetKind: MessageReaction.TargetKind?
    @State private var reactionPickerTargetId: String?
    @State private var composerKeyMonitor: Any?

    var body: some View {
        VStack(spacing: 0) {
            ScrollViewReader { scrollProxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 12, pinnedViews: [.sectionHeaders]) {
                        ForEach(viewModel.groups) { group in
                            Section(header: dayHeader(group.date)) {
                                ForEach(group.items) { item in
                                    rowFor(item: item)
                                        .id(item.id)
                                }
                            }
                        }
                        if viewModel.isLoading {
                            ProgressView().padding()
                        }
                    }
                    .padding(.horizontal, 16)
                }
                .onChange(of: viewModel.groups.first?.items.first?.id) { _ in
                    if let firstId = viewModel.groups.first?.items.first?.id {
                        withAnimation(.easeOut) { scrollProxy.scrollTo(firstId, anchor: .bottom) }
                    }
                }
            }

            ChatComposerView(
                draft: $draft,
                replyTarget: viewModel.replyTarget,
                onCancelReply: { viewModel.replyTarget = nil },
                onSend: sendDraft
            )
        }
        .overlay(alignment: .top) {
            if let targetKind = reactionPickerTargetKind, let targetId = reactionPickerTargetId {
                ReactionPickerView(
                    onPick: { emoji in
                        Task { await viewModel.toggleReaction(target: targetKind, targetId: targetId, emoji: emoji) }
                        reactionPickerTargetKind = nil
                        reactionPickerTargetId = nil
                    },
                    onMore: {
                        ReactionPickerView.openSystemEmojiPicker()
                        reactionPickerTargetKind = nil
                        reactionPickerTargetId = nil
                    }
                )
                .padding(.top, 60)
            }
        }
        .onAppear {
            composerKeyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
                if event.keyCode == 36 && event.modifierFlags.contains(.command) {
                    sendDraft()
                    return nil
                }
                return event
            }
        }
        .onDisappear {
            if let composerKeyMonitor {
                NSEvent.removeMonitor(composerKeyMonitor)
                self.composerKeyMonitor = nil
            }
        }
    }

    private func sendDraft() {
        let body = draft
        draft = ""
        Task { await viewModel.sendChat(body: body) }
    }

    @ViewBuilder
    private func rowFor(item: TimelineItem) -> some View {
        let myUid = appState.currentUser?.id
        switch item {
        case .video(let v):
            let key = "video:" + (v.id ?? "")
            let aggs = (viewModel.reactionsByTargetId[key] ?? [:]).values.sorted(by: { $0.count > $1.count })
            MessageRowView(
                message: v,
                isMine: v.senderUid == myUid,
                isExpanded: viewModel.expandedMessageId == v.id,
                onTap: {
                    if viewModel.expandedMessageId == v.id {
                        viewModel.expandedMessageId = nil
                    } else {
                        viewModel.expandedMessageId = v.id
                    }
                },
                cacheService: cacheService,
                inlineController: viewModel.inlineController,
                reactions: Array(aggs),
                onReply: {
                    viewModel.replyTarget = .video(id: v.id ?? "", sender: v.senderNickname, captureMode: v.captureMode)
                },
                onReact: {
                    reactionPickerTargetKind = .video
                    reactionPickerTargetId = v.id
                },
                onSave: { Task { await viewModel.save(message: v, cacheService: cacheService, currentUid: myUid) } },
                onDelete: { Task { await viewModel.delete(message: v, currentUid: myUid) } },
                onToggleReaction: { emoji in
                    guard let vid = v.id else { return }
                    Task { await viewModel.toggleReaction(target: .video, targetId: vid, emoji: emoji) }
                }
            )
        case .chat(let c):
            let key = "chat:" + (c.id ?? "")
            let aggs = (viewModel.reactionsByTargetId[key] ?? [:]).values.sorted(by: { $0.count > $1.count })
            let preview = replyPreview(for: c)
            let roomMemberCount = appState.rooms.first(where: { $0.id == c.roomId })?.memberUids.count ?? 0
            ChatMessageRowView(
                message: c,
                isMine: c.senderUid == myUid,
                showsSender: roomMemberCount >= 3,
                replyPreview: preview,
                reactions: Array(aggs),
                onReply: {
                    viewModel.replyTarget = .chat(id: c.id ?? "", sender: c.senderNickname, preview: c.body)
                },
                onReact: {
                    reactionPickerTargetKind = .chat
                    reactionPickerTargetId = c.id
                },
                onDelete: { Task { await viewModel.deleteChat(messageId: c.id ?? "") } },
                onToggleReaction: { emoji in
                    guard let cid = c.id else { return }
                    Task { await viewModel.toggleReaction(target: .chat, targetId: cid, emoji: emoji) }
                }
            )
        }
    }

    private func replyPreview(for chat: ChatMessage) -> ChatMessageRowView.ReplyPreview? {
        if let replyChatId = chat.replyToChatId,
           let target = findChat(by: replyChatId) {
            return .chat(sender: target.senderNickname, body: target.body)
        }
        if let replyVideoId = chat.replyToVideoId,
           let target = findVideo(by: replyVideoId) {
            return .video(sender: target.senderNickname, captureMode: target.captureMode)
        }
        return nil
    }

    private func findChat(by id: String) -> ChatMessage? {
        for group in viewModel.groups {
            for item in group.items {
                if case .chat(let c) = item, c.id == id { return c }
            }
        }
        return nil
    }

    private func findVideo(by id: String) -> VideoMessage? {
        for group in viewModel.groups {
            for item in group.items {
                if case .video(let v) = item, v.id == id { return v }
            }
        }
        return nil
    }

    private func dayHeader(_ date: Date) -> some View {
        Text(dayLabel(date))
            .font(.caption.weight(.semibold))
            .foregroundStyle(.secondary)
            .padding(.vertical, 6)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color(NSColor.windowBackgroundColor))
    }

    private func dayLabel(_ date: Date) -> String {
        let cal = Calendar.current
        if cal.isDateInToday(date) { return "오늘" }
        if cal.isDateInYesterday(date) { return "어제" }
        return date.formatted(.dateTime.month().day().weekday(.abbreviated))
    }
}
