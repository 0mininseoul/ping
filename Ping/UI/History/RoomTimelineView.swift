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
    @State private var scrollWheelMonitor: Any?
    @State private var revealOffset: CGFloat = 0
    private let revealMax: CGFloat = -68
    // 시간 라벨이 평소엔 row trailing + 60pt 우측 (화면 밖). row가 좌측으로 이동하면 함께 들어옴.
    private let labelOutset: CGFloat = 60

    var body: some View {
        VStack(spacing: 0) {
            ScrollViewReader { scrollProxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 2, pinnedViews: [.sectionHeaders]) {
                        if viewModel.groups.isEmpty, !viewModel.isLoading {
                            emptyTimelineState
                        } else {
                            ForEach(viewModel.groups) { group in
                                Section(header: dayHeader(group.date)) {
                                    ForEach(group.items) { item in
                                        rowFor(item: item)
                                            .overlay(alignment: .trailing) {
                                                if let date = item.createdAt {
                                                    Text(date.formatted(.dateTime.hour().minute()))
                                                        .font(.caption2)
                                                        .foregroundStyle(.tertiary)
                                                        .frame(width: labelOutset, alignment: .leading)
                                                        // 평소 화면 밖 우측에 위치. row offset이 -labelOutset이면 정확히 trailing edge에 들어옴.
                                                        .offset(x: labelOutset)
                                                        .opacity(min(1, abs(revealOffset) / 50))
                                                }
                                            }
                                            .offset(x: revealOffset)
                                            .id(item.id)
                                    }
                                }
                            }
                        }
                        if viewModel.isLoading {
                            ProgressView().padding()
                        }
                    }
                    .padding(.horizontal, 16)
                }
                .onChange(of: viewModel.groups.last?.items.last?.id) { _ in
                    if let lastId = viewModel.groups.last?.items.last?.id {
                        withAnimation(.easeOut) { scrollProxy.scrollTo(lastId, anchor: .bottom) }
                    }
                }
                .onAppear {
                    if let lastId = viewModel.groups.last?.items.last?.id {
                        scrollProxy.scrollTo(lastId, anchor: .bottom)
                    }
                    if scrollWheelMonitor == nil {
                        scrollWheelMonitor = NSEvent.addLocalMonitorForEvents(matching: .scrollWheel) { [self] event in
                            // 수평 swipe만 처리 (수직 스크롤은 ScrollView에 위임)
                            guard abs(event.scrollingDeltaX) > abs(event.scrollingDeltaY) else { return event }
                            let delta = event.scrollingDeltaX
                            if delta < 0 {
                                // 좌측 swipe → 시간 라벨 노출
                                revealOffset = max(revealMax, revealOffset + delta * 0.6)
                            } else {
                                // 우측 swipe → 복원 방향 허용
                                revealOffset = min(0, revealOffset + delta * 0.6)
                            }
                            // 스크롤 제스처 종료 감지 → spring 복원
                            let isEnded = event.phase == .ended || event.phase == .cancelled
                                || event.momentumPhase == .ended || event.momentumPhase == .cancelled
                            if isEnded {
                                withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                                    revealOffset = 0
                                }
                            }
                            // 이벤트 소비 (ScrollView 수평 스크롤 방지)
                            return nil
                        }
                    }
                }
                .simultaneousGesture(
                    DragGesture(minimumDistance: 10)
                        .onChanged { value in
                            if abs(value.translation.width) > abs(value.translation.height) {
                                if value.translation.width < 0 {
                                    revealOffset = max(revealMax, value.translation.width)
                                }
                            }
                        }
                        .onEnded { _ in
                            withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                                revealOffset = 0
                            }
                        }
                )
            }

            ChatComposerView(
                draft: $draft,
                replyTarget: viewModel.replyTarget,
                onCancelReply: { viewModel.replyTarget = nil },
                onSend: sendDraft
            )
        }
        .overlay(alignment: .bottom) {
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
                .padding(.bottom, 80)
                .transition(.opacity)
            }
        }
        .onAppear {
            composerKeyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
                // Only intercept when TextEditor inside this view has focus
                guard let responder = NSApp.keyWindow?.firstResponder,
                      responder.isKind(of: NSTextView.self) else {
                    return event
                }
                // keyCode 36 = Return
                guard event.keyCode == 36 else { return event }

                let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
                // Shift+Enter → newline (let TextEditor handle)
                if flags.contains(.shift) {
                    return event
                }
                // Cmd+Enter sends. Plain Enter remains a newline in the TextEditor.
                if flags == .command {
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
            if let scrollWheelMonitor {
                NSEvent.removeMonitor(scrollWheelMonitor)
                self.scrollWheelMonitor = nil
            }
        }
        .alert("오류", isPresented: Binding<Bool>(
            get: { viewModel.lastErrorMessage != nil },
            set: { if !$0 { viewModel.lastErrorMessage = nil } }
        ), actions: {
            Button("확인") { viewModel.lastErrorMessage = nil }
        }, message: {
            Text(viewModel.lastErrorMessage ?? "")
        })
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

    private var emptyTimelineState: some View {
        VStack(spacing: 8) {
            Image(systemName: "bubble.left.and.bubble.right")
                .font(.system(size: 30, weight: .semibold))
                .foregroundStyle(.tertiary)

            Text("아직 기록 없음")
                .font(.callout.weight(.semibold))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, minHeight: 360)
    }

    private func dayLabel(_ date: Date) -> String {
        let cal = Calendar.current
        if cal.isDateInToday(date) { return "오늘" }
        if cal.isDateInYesterday(date) { return "어제" }
        return date.formatted(.dateTime.month().day().weekday(.abbreviated))
    }
}
