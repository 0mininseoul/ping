import SwiftUI
import AVKit
import PingKit

/// Downloads and plays a ping's 3-second clip on the watch, then marks it seen.
struct WatchPlaybackView: View {
    let messageId: String

    @State private var player: AVPlayer?
    @State private var statusText = "불러오는 중…"

    var body: some View {
        Group {
            if let player {
                VideoPlayer(player: player)
                    .onAppear { player.play() }
            } else {
                VStack(spacing: 8) {
                    ProgressView()
                    Text(statusText)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .task { await load() }
    }

    private func load() async {
        guard let client = WatchSessionStore.shared.makeClient() else {
            statusText = "연결이 필요합니다"
            return
        }
        do {
            guard let message = try await client.getMessage(messageId: messageId) else {
                statusText = "메시지를 찾을 수 없습니다"
                return
            }
            let data = try await client.downloadVideo(message)
            let tempURL = FileManager.default.temporaryDirectory
                .appendingPathComponent(message.videoId + ".mp4")
            try data.write(to: tempURL)
            player = AVPlayer(url: tempURL)
            try? await client.markSeen(messageId: messageId)
        } catch {
            statusText = "재생에 실패했습니다"
        }
    }
}
