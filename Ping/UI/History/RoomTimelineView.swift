import SwiftUI
import AppKit

struct RoomTimelineView: View {
    @ObservedObject var viewModel: HistoryViewModel
    let cacheService: HistoryCacheService
    @ObservedObject var appState: AppState
    var usesExternalScreenFaceExpansion: Bool = false
    var onScreenFaceExpansionChange: (ScreenFaceExpansionAnchor?, ScreenFaceExpansionContext?) -> Void = { _, _ in }

    @State private var draft: String = ""
    @State private var reactionPickerTargetKind: MessageReaction.TargetKind?
    @State private var reactionPickerTargetId: String?
    @State private var composerKeyMonitor: Any?
    @State private var scrollWheelMonitor: Any?
    @State private var revealResetTask: Task<Void, Never>?
    @State private var revealOffset: CGFloat = 0
    private let timestampWidth: CGFloat = 78
    private let timestampGap: CGFloat = 16
    private let timelineBottomInset: CGFloat = 24
    private let videoExpansionAnimation: Animation = .easeOut(duration: 0.18)
    private let revealResetAnimation: Animation = .easeOut(duration: 0.10)
    private var revealMax: CGFloat { -(timestampWidth + timestampGap) }

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
                                        timelineRow(for: item)
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
                    .padding(.bottom, timelineBottomInset)
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
                            let phase = event.phase
                            if phase.contains(.ended) || phase.contains(.cancelled) {
                                let shouldConsume = revealOffset != 0
                                if revealOffset != 0 { resetRevealOffset() }
                                return shouldConsume ? nil : event
                            }
                            guard abs(event.scrollingDeltaX) > abs(event.scrollingDeltaY) else { return event }
                            let delta = event.scrollingDeltaX

                            if event.momentumPhase != [] {
                                if revealOffset != 0 { resetRevealOffset() }
                                return nil
                            }

                            if delta < 0 {
                                // 좌측 swipe → 시간 라벨 노출
                                updateRevealOffset(revealOffset + delta * 0.6)
                            } else {
                                // 우측 swipe → 복원 방향 허용
                                updateRevealOffset(revealOffset + delta * 0.6)
                            }
                            if phase == [] {
                                scheduleRevealReset(after: 60_000_000)
                            } else {
                                revealResetTask?.cancel()
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
                                    updateRevealOffset(value.translation.width)
                                }
                            }
                        }
                        .onEnded { _ in
                            resetRevealOffset()
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
            onScreenFaceExpansionChange(nil, nil)
            revealResetTask?.cancel()
            revealResetTask = nil
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

    private func scheduleRevealReset(after delay: UInt64 = 160_000_000) {
        revealResetTask?.cancel()
        revealResetTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: delay)
            guard !Task.isCancelled else { return }
            resetRevealOffset()
        }
    }

    private func updateRevealOffset(_ value: CGFloat) {
        let clamped = min(0, max(revealMax, value))
        guard abs(clamped - revealOffset) >= 0.5 else { return }
        var transaction = Transaction()
        transaction.animation = nil
        withTransaction(transaction) {
            revealOffset = clamped
        }
    }

    private func resetRevealOffset() {
        revealResetTask?.cancel()
        guard revealOffset != 0 else { return }
        withAnimation(revealResetAnimation) {
            revealOffset = 0
        }
    }

    private func timelineRow(for item: TimelineItem) -> some View {
        ZStack(alignment: .trailing) {
            timestampLabel(for: item)
            rowFor(item: item)
                .offset(x: revealOffset)
        }
    }

    @ViewBuilder
    private func timestampLabel(for item: TimelineItem) -> some View {
        if let date = item.createdAt {
            Text(date.formatted(.dateTime.hour().minute()))
                .font(.caption2)
                .foregroundStyle(.tertiary)
                .frame(width: timestampWidth, alignment: .leading)
                .opacity(min(1, abs(revealOffset) / (timestampWidth * 0.7)))
                .allowsHitTesting(false)
        }
    }

    @ViewBuilder
    private func rowFor(item: TimelineItem) -> some View {
        let myUid = appState.currentUser?.id
        switch item {
        case .video(let v):
            let key = "video:" + (v.id ?? "")
            let aggs = (viewModel.reactionsByTargetId[key] ?? [:]).values.sorted(by: { $0.count > $1.count })
            let isMine = v.senderUid == myUid
            let roomMemberCount = appState.rooms.first(where: { $0.id == v.roomId })?.memberUids.count ?? 0
            MessageRowView(
                message: v,
                isMine: isMine,
                isExpanded: viewModel.expandedMessageId == v.id,
                showsSender: roomMemberCount >= 3,
                onTap: {
                    withAnimation(videoExpansionAnimation) {
                        if viewModel.expandedMessageId == v.id {
                            viewModel.expandedMessageId = nil
                        } else {
                            viewModel.expandedMessageId = v.id
                        }
                    }
                },
                cacheService: cacheService,
                inlineController: viewModel.inlineController,
                archivePeerName: archivePeerName(for: v, isMine: isMine, myUid: myUid),
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
                },
                canSave: v.canBeSavedLocally(by: myUid),
                usesExternalScreenFaceExpansion: usesExternalScreenFaceExpansion,
                onScreenFaceExpansionChange: onScreenFaceExpansionChange
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
