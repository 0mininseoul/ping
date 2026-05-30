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

    private var myUid: String { account.session.userId }

    var body: some View {
        VStack(spacing: 0) {
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(spacing: 10) {
                        ForEach(items) { item in
                            row(item).id(item.id)
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
                Text(chat.preview.isEmpty ? " " : chat.preview)
                    .font(.body)
                    .foregroundStyle(mine ? .white : Color(uiColor: .label))
                    .padding(.horizontal, 12).padding(.vertical, 8)
                    .background(
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .fill(mine ? Color.accentColor : Color.gray.opacity(0.18))
                    )
            }
            if !mine { Spacer(minLength: 40) }
        }
    }

    // MARK: - Reply bar

    private var replyBar: some View {
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
        .padding(.horizontal, 12).padding(.vertical, 8)
        .background(.bar)
    }

    private var canSend: Bool {
        !draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !sending
    }

    // MARK: - Actions

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
        try? await client.markRoomRead(roomId: roomId)
    }

    private func send() {
        let text = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        draft = ""
        sending = true
        Task {
            if let client = AppEnvironment.shared.makeClient() {
                try? await client.sendChat(roomId: roomId, body: text)
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
