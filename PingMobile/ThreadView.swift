import SwiftUI
import AVKit
import AVFoundation
import PingKit

/// A room's thread: received pings (tap to play the 3s clip) and text chat,
/// interleaved by time, with a text (dictation) reply bar. No recording here —
/// composing a ping stays a Mac/PC act.
struct ThreadView: View {
    let account: PairedAccount
    let roomId: String

    @State private var items: [ThreadItem] = []
    @State private var draft = ""
    @State private var isLoading = true
    @State private var sending = false
    @State private var loadingVideoId: String?
    @State private var playable: PlayableVideo?
    @StateObject private var thumbnails = ThumbnailStore()
    @State private var timestampRevealOffset: CGFloat = 0
    @State private var replyTarget: ReplyTarget?
    @State private var reactionsByTargetId: [String: [String: ThreadReactionAggregate]] = [:]

    private let timestampWidth: CGFloat = 64
    private let timestampGap: CGFloat = 12
    private let timestampResetAnimation: Animation = .easeOut(duration: 0.10)
    private var timestampRevealMax: CGFloat { -(timestampWidth + timestampGap) }
    private let quickReactionEmojis = ["👍", "❤️", "😂", "😮", "😢", "🙏"]

    private var myUid: String { account.session.userId }

    var body: some View {
        VStack(spacing: 0) {
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(spacing: 10) {
                        ForEach(items) { item in
                            timestampRevealRow(for: item).id(item.id)
                        }
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 12)
                }
                // Rest at the bottom (newest) on entry without an animated scroll.
                .defaultScrollAnchor(.bottom)
                .onChange(of: items.count) { _, _ in
                    if let last = items.last { proxy.scrollTo(last.id, anchor: .bottom) }
                }
                .overlay { if isLoading && items.isEmpty { ProgressView() } }
                .simultaneousGesture(timestampRevealGesture)
            }
            replyBar
        }
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
        .task { await load() }
        .fullScreenCover(item: $playable) { VideoPlayerScreen(video: $0) }
    }

    private var title: String {
        items.compactMap { item -> String? in
            if case let .video(m) = item, m.senderUid != myUid { return m.senderNickname }
            if case let .chat(c) = item, c.senderUid != myUid { return c.senderNickname }
            return nil
        }.first ?? "대화"
    }

    private func timestampRevealRow(for item: ThreadItem) -> some View {
        ZStack(alignment: .trailing) {
            timestampLabel(for: item)
            row(item)
                .offset(x: timestampRevealOffset)
        }
    }

    private func timestampLabel(for item: ThreadItem) -> some View {
        Text(item.date.formatted(.dateTime.hour().minute()))
            .font(.caption2)
            .foregroundStyle(.tertiary)
            .frame(width: timestampWidth, alignment: .leading)
            .opacity(min(1, abs(timestampRevealOffset) / (timestampWidth * 0.7)))
            .allowsHitTesting(false)
    }

    // MARK: - Rows

    @ViewBuilder
    private func row(_ item: ThreadItem) -> some View {
        switch item {
        case .video(let message):
            videoRow(message)
        case .chat(let chat):
            chatRow(chat)
        }
    }

    private func videoRow(_ message: VideoMessage) -> some View {
        let mine = message.senderUid == myUid
        let size = thumbnailSize(for: message)
        return HStack {
            if mine { Spacer(minLength: 60) }
            VStack(alignment: mine ? .trailing : .leading, spacing: 3) {
                if !mine {
                    Text(message.senderNickname).font(.caption2).foregroundStyle(.secondary)
                }
                Button { play(message) } label: {
                    VideoThumbnailView(store: thumbnails, message: message)
                        .frame(width: size.width, height: size.height)
                        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: 16, style: .continuous)
                                .strokeBorder(Color.primary.opacity(0.06))
                        )
                }
                .buttonStyle(.plain)
                .contextMenu {
                    messageContextMenu(
                        target: .video,
                        targetId: message.id,
                        onReply: {
                            replyTarget = .video(
                                id: message.id,
                                sender: message.senderNickname,
                                preview: videoReplyPreview(message)
                            )
                        }
                    )
                }
                let reactions = reactions(for: .video, targetId: message.id)
                if !reactions.isEmpty {
                    reactionStrip(reactions, target: .video, targetId: message.id)
                }
            }
            if !mine { Spacer(minLength: 60) }
        }
    }

    /// Mirror the macOS thumbnail sizing: square for face-only, otherwise a
    /// width-fixed tile whose height follows the clip's aspect ratio.
    private func thumbnailSize(for message: VideoMessage) -> CGSize {
        if message.captureMode == "face_only" {
            return CGSize(width: 150, height: 150)
        }
        let aspect = max(0.5, min(3.0, message.aspectRatio ?? 1.78))
        let width: CGFloat = 190
        return CGSize(width: width, height: width / aspect)
    }

    private func chatRow(_ chat: PingChatMessage) -> some View {
        let mine = chat.senderUid == myUid
        return HStack {
            if mine { Spacer(minLength: 40) }
            VStack(alignment: mine ? .trailing : .leading, spacing: 2) {
                if !mine {
                    Text(chat.senderNickname).font(.caption2).foregroundStyle(.secondary)
                }
                if let preview = replyPreview(for: chat) {
                    quotedReplyPreview(preview, mine: mine)
                }
                VStack(alignment: mine ? .trailing : .leading, spacing: 6) {
                    if chat.hasImage {
                        ChatImageAttachmentView(message: chat)
                    }

                    if !chat.body.isEmpty {
                        Text(chat.body)
                            .font(.body)
                            .foregroundStyle(mine ? .white : Color(uiColor: .label))
                            .padding(.horizontal, 12).padding(.vertical, 8)
                            .background(
                                RoundedRectangle(cornerRadius: 16, style: .continuous)
                                    .fill(mine ? Color.accentColor : Color.gray.opacity(0.18))
                            )
                    }
                }
                .contextMenu {
                    messageContextMenu(
                        target: .chat,
                        targetId: chat.id,
                        onReply: {
                            replyTarget = .chat(id: chat.id, sender: chat.senderNickname, preview: chat.preview)
                        }
                    )
                }
                let reactions = reactions(for: .chat, targetId: chat.id)
                if !reactions.isEmpty {
                    reactionStrip(reactions, target: .chat, targetId: chat.id)
                }
            }
            if !mine { Spacer(minLength: 40) }
        }
    }

    // MARK: - Reply bar

    private var replyBar: some View {
        VStack(spacing: 6) {
            if let replyTarget {
                HStack(spacing: 8) {
                    Rectangle()
                        .fill(Color.accentColor.opacity(0.65))
                        .frame(width: 3)
                        .clipShape(Capsule())
                    VStack(alignment: .leading, spacing: 1) {
                        Text(replyTarget.sender)
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                        Text(replyTarget.preview)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                    Spacer()
                    Button {
                        self.replyTarget = nil
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.body)
                            .foregroundStyle(.tertiary)
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, 14)
                .padding(.top, 8)
            }

            HStack(spacing: 10) {
                TextField("메시지 입력 (마이크로 받아쓰기)", text: $draft, axis: .vertical)
                    .textFieldStyle(.plain)
                    .padding(.horizontal, 14).padding(.vertical, 9)
                    .background(Capsule().fill(Color(uiColor: .secondarySystemBackground)))
                    .lineLimit(1...4)
                Button { send() } label: {
                    Image(systemName: "arrow.up.circle.fill")
                        .font(.system(size: 30))
                        .foregroundStyle(canSend ? Color.accentColor : Color.secondary)
                }
                .disabled(!canSend)
            }
            .padding(.horizontal, 12)
            .padding(.bottom, 8)
            .padding(.top, replyTarget == nil ? 8 : 0)
        }
        .background(.bar)
    }

    private var canSend: Bool {
        !draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !sending
    }

    // MARK: - Actions

    private var timestampRevealGesture: some Gesture {
        DragGesture(minimumDistance: 10)
            .onChanged { value in
                guard abs(value.translation.width) > abs(value.translation.height) else { return }

                if value.translation.width < 0 || timestampRevealOffset != 0 {
                    updateTimestampRevealOffset(value.translation.width)
                }
            }
            .onEnded { _ in
                resetTimestampRevealOffset()
            }
    }

    private func updateTimestampRevealOffset(_ value: CGFloat) {
        let clamped = min(0, max(timestampRevealMax, value))
        guard abs(clamped - timestampRevealOffset) >= 0.5 else { return }

        var transaction = Transaction()
        transaction.animation = nil
        withTransaction(transaction) {
            timestampRevealOffset = clamped
        }
    }

    private func resetTimestampRevealOffset() {
        guard timestampRevealOffset != 0 else { return }
        withAnimation(timestampResetAnimation) {
            timestampRevealOffset = 0
        }
    }

    private func load() async {
        guard let client = AppEnvironment.shared.makeClient() else {
            isLoading = false
            return
        }
        let videos = (try? await client.roomMessages(roomId: roomId)) ?? []
        let chats = (try? await client.roomChatMessages(roomId: roomId)) ?? []
        var merged: [ThreadItem] = videos.map { .video($0) } + chats.map { .chat($0) }
        merged.sort { $0.date < $1.date }
        items = merged
        isLoading = false
        thumbnails.prefetch(videos)
        await refreshReactions()
        try? await client.markRoomRead(roomId: roomId)
    }

    private func send() {
        let text = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        draft = ""
        sending = true
        let target = replyTarget
        replyTarget = nil
        Task {
            if let client = AppEnvironment.shared.makeClient() {
                let replyChatId: String?
                let replyVideoId: String?
                switch target {
                case .chat(let id, _, _):
                    replyChatId = id
                    replyVideoId = nil
                case .video(let id, _, _):
                    replyChatId = nil
                    replyVideoId = id
                case .none:
                    replyChatId = nil
                    replyVideoId = nil
                }
                _ = try? await client.sendChat(roomId: roomId, body: text, replyToChatId: replyChatId, replyToVideoId: replyVideoId)
            }
            await load()
            sending = false
        }
    }

    private func play(_ message: VideoMessage) {
        guard loadingVideoId == nil else { return }
        loadingVideoId = message.id
        Task {
            defer { loadingVideoId = nil }
            // Reuse the same cached clip the thumbnail downloaded.
            guard let url = try? await VideoCache.shared.localURL(for: message) else { return }
            playable = PlayableVideo(id: message.id, url: url)
            if let client = AppEnvironment.shared.makeClient() {
                try? await client.markSeen(messageId: message.id)
            }
        }
    }

    private func refreshReactions() async {
        guard let client = AppEnvironment.shared.makeClient() else { return }
        let chatIds = items.compactMap { item -> String? in
            if case .chat(let message) = item { return message.id }
            return nil
        }
        let videoIds = items.compactMap { item -> String? in
            if case .video(let message) = item { return message.id }
            return nil
        }
        guard !chatIds.isEmpty || !videoIds.isEmpty else {
            reactionsByTargetId = [:]
            return
        }
        guard let reactions = try? await client.messageReactions(chatIds: chatIds, videoIds: videoIds) else { return }
        var next: [String: [String: ThreadReactionAggregate]] = [:]
        for reaction in reactions {
            let key = reactionKey(target: reaction.targetKind, targetId: reaction.targetId)
            next[key, default: [:]][reaction.emoji] = ThreadReactionAggregate(
                emoji: reaction.emoji,
                count: reaction.totalCount,
                myReacted: reaction.myReacted
            )
        }
        reactionsByTargetId = next
    }

    private func toggleReaction(target kind: PingMessageReaction.TargetKind, targetId: String, emoji: String) {
        Task {
            guard let client = AppEnvironment.shared.makeClient() else { return }
            _ = try? await client.toggleReaction(target: kind, targetId: targetId, emoji: emoji)
            await refreshReactions()
        }
    }

    @ViewBuilder
    private func messageContextMenu(
        target kind: PingMessageReaction.TargetKind,
        targetId: String,
        onReply: @escaping () -> Void
    ) -> some View {
        Button {
            onReply()
        } label: {
            Label("답장", systemImage: "arrowshape.turn.up.left")
        }

        Menu {
            ForEach(quickReactionEmojis, id: \.self) { emoji in
                Button(emoji) {
                    toggleReaction(target: kind, targetId: targetId, emoji: emoji)
                }
            }
        } label: {
            Label("이모지 반응", systemImage: "face.smiling")
        }
    }

    private func reactionStrip(
        _ reactions: [ThreadReactionAggregate],
        target kind: PingMessageReaction.TargetKind,
        targetId: String
    ) -> some View {
        HStack(spacing: 4) {
            ForEach(reactions, id: \.emoji) { reaction in
                Button {
                    toggleReaction(target: kind, targetId: targetId, emoji: reaction.emoji)
                } label: {
                    HStack(spacing: 2) {
                        Text(reaction.emoji)
                        if reaction.count > 1 {
                            Text("\(reaction.count)")
                                .font(.caption2.weight(.medium))
                        }
                    }
                    .font(.caption)
                    .foregroundStyle(Color(uiColor: .label))
                    .padding(.horizontal, 7)
                    .padding(.vertical, 3)
                    .background(
                        Capsule()
                            .fill(reaction.myReacted ? Color.accentColor.opacity(0.20) : Color(uiColor: .secondarySystemBackground))
                    )
                }
                .buttonStyle(.plain)
            }
        }
    }

    private func reactions(
        for kind: PingMessageReaction.TargetKind,
        targetId: String
    ) -> [ThreadReactionAggregate] {
        let key = reactionKey(target: kind, targetId: targetId)
        let values = reactionsByTargetId[key].map { Array($0.values) } ?? []
        return values.sorted {
            if $0.count == $1.count { return $0.emoji < $1.emoji }
            return $0.count > $1.count
        }
    }

    private func reactionKey(target kind: PingMessageReaction.TargetKind, targetId: String) -> String {
        "\(kind.rawValue):\(targetId)"
    }

    private func replyPreview(for chat: PingChatMessage) -> ReplyPreview? {
        if let replyToChatId = chat.replyToChatId {
            if let target = findChat(id: replyToChatId) {
                return ReplyPreview(sender: target.senderNickname, preview: target.preview)
            }
            return ReplyPreview(sender: "답장", preview: "이전 메시지")
        }
        if let replyToVideoId = chat.replyToVideoId {
            if let target = findVideo(id: replyToVideoId) {
                return ReplyPreview(sender: target.senderNickname, preview: videoReplyPreview(target))
            }
            return ReplyPreview(sender: "답장", preview: "영상 메시지")
        }
        return nil
    }

    private func quotedReplyPreview(_ preview: ReplyPreview, mine: Bool) -> some View {
        HStack(spacing: 5) {
            Rectangle()
                .fill(Color.secondary.opacity(0.38))
                .frame(width: 2)
            VStack(alignment: .leading, spacing: 1) {
                Text(preview.sender)
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.secondary)
                Text(preview.preview)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .background(Color(uiColor: .secondarySystemBackground).opacity(0.75))
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .frame(maxWidth: 260, alignment: mine ? .trailing : .leading)
    }

    private func findChat(id: String) -> PingChatMessage? {
        items.compactMap { item -> PingChatMessage? in
            if case .chat(let message) = item, message.id == id { return message }
            return nil
        }.first
    }

    private func findVideo(id: String) -> VideoMessage? {
        items.compactMap { item -> VideoMessage? in
            if case .video(let message) = item, message.id == id { return message }
            return nil
        }.first
    }

    private func videoReplyPreview(_ message: VideoMessage) -> String {
        message.captureMode == "screen_face" ? "화면+얼굴 영상" : "얼굴 영상"
    }
}

/// One entry in a room thread, sortable by time.
private enum ThreadItem: Identifiable {
    case video(VideoMessage)
    case chat(PingChatMessage)

    var id: String {
        switch self {
        case .video(let m): return "v_\(m.id)"
        case .chat(let c): return "c_\(c.id)"
        }
    }

    var date: Date {
        switch self {
        case .video(let m): return m.createdAt
        case .chat(let c): return c.createdAt
        }
    }
}

private enum ReplyTarget: Hashable {
    case chat(id: String, sender: String, preview: String)
    case video(id: String, sender: String, preview: String)

    var sender: String {
        switch self {
        case .chat(_, let sender, _), .video(_, let sender, _):
            return sender
        }
    }

    var preview: String {
        switch self {
        case .chat(_, _, let preview), .video(_, _, let preview):
            return preview
        }
    }
}

private struct ReplyPreview: Hashable {
    let sender: String
    let preview: String
}

private struct ThreadReactionAggregate: Hashable {
    let emoji: String
    let count: Int
    let myReacted: Bool
}

/// A downloaded clip ready to play.
struct PlayableVideo: Identifiable {
    let id: String
    let url: URL
}

/// Fullscreen looping player for the 3-second clip.
private struct VideoPlayerScreen: View {
    let video: PlayableVideo
    @Environment(\.dismiss) private var dismiss
    @State private var player: AVPlayer?

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            if let player {
                VideoPlayer(player: player).ignoresSafeArea()
            }
            VStack {
                HStack {
                    Spacer()
                    Button { dismiss() } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 30))
                            .foregroundStyle(.white.opacity(0.85))
                            .padding()
                    }
                }
                Spacer()
            }
        }
        .onAppear {
            let p = AVPlayer(url: video.url)
            player = p
            p.play()
            NotificationCenter.default.addObserver(
                forName: .AVPlayerItemDidPlayToEndTime,
                object: p.currentItem,
                queue: .main
            ) { _ in
                p.seek(to: .zero)
                p.play()
            }
        }
        .onDisappear { player?.pause() }
    }
}
