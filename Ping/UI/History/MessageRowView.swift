import SwiftUI

struct MessageRowView: View {
    let message: VideoMessage
    let isMine: Bool
    let isExpanded: Bool
    let onTap: () -> Void
    let cacheService: HistoryCacheService
    @ObservedObject var inlineController: InlinePlayerController
    let reactions: [HistoryViewModel.ReactionAggregate]
    let onReply: () -> Void
    let onReact: () -> Void
    let onSave: () -> Void
    let onDelete: () -> Void
    let onToggleReaction: (String) -> Void

    var body: some View {
        HStack {
            if isMine { Spacer() }
            VStack(alignment: isMine ? .trailing : .leading, spacing: 4) {
                if isExpanded {
                    InlinePlayerView(message: message, cacheService: cacheService, controller: inlineController)
                } else {
                    thumbnail
                }
                metadata
                if !reactions.isEmpty {
                    HStack(spacing: 4) {
                        ForEach(reactions, id: \.emoji) { agg in
                            Button(action: { onToggleReaction(agg.emoji) }) {
                                HStack(spacing: 2) {
                                    Text(agg.emoji)
                                    if agg.count > 1 {
                                        Text("\(agg.count)").font(.caption2).foregroundStyle(.secondary)
                                    }
                                }
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(agg.myReacted ? Color.accentColor.opacity(0.2) : Color.gray.opacity(0.1))
                                .clipShape(Capsule())
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
            .contextMenu {
                Button(action: onReply) {
                    Label("답장", systemImage: "arrowshape.turn.up.left")
                }
                Button(action: onReact) {
                    Label("이모지 반응", systemImage: "face.smiling")
                }
                Button(action: onSave) {
                    Label("저장", systemImage: "arrow.down.circle")
                }
                Divider()
                Button(role: .destructive, action: onDelete) {
                    Label("삭제", systemImage: "trash")
                }
            }
            if !isMine { Spacer() }
        }
        .padding(.vertical, 1)
        .contentShape(Rectangle())
        .onTapGesture { onTap() }
    }

    private var thumbnail: some View {
        Group {
            if message.captureMode == .faceOnly {
                VideoThumbnailView(message: message, cacheService: cacheService)
                    .frame(width: 60, height: 60)
                    .clipShape(Circle())
            } else {
                VideoThumbnailView(message: message, cacheService: cacheService)
                    .aspectRatio(message.aspectRatio ?? 1.78, contentMode: .fit)
                    .frame(maxWidth: 90)
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            }
        }
        .overlay(
            Image(systemName: "play.fill")
                .font(.caption)
                .foregroundStyle(.white)
                .padding(6)
                .background(Circle().fill(Color.black.opacity(0.35)))
                .allowsHitTesting(false)
        )
    }

    private var metadata: some View {
        HStack(spacing: 6) {
            if message.captureMode == .screenFace {
                Image(systemName: "rectangle.fill").font(.caption2)
            } else {
                Image(systemName: "circle.fill").font(.caption2)
            }
        }
        .foregroundStyle(.secondary)
    }
}
