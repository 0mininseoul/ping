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

    @State private var isHovered: Bool = false

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
            if isHovered && !isExpanded {
                HStack(spacing: 6) {
                    Button(action: onReply) { Image(systemName: "arrowshape.turn.up.left").imageScale(.small) }.buttonStyle(.plain)
                    Button(action: onReact) { Image(systemName: "face.smiling").imageScale(.small) }.buttonStyle(.plain)
                    Button(action: onSave) { Image(systemName: "arrow.down.circle").imageScale(.small) }.buttonStyle(.plain)
                    Button(action: onDelete) { Image(systemName: "trash").imageScale(.small) }.buttonStyle(.plain)
                }
                .foregroundStyle(.secondary)
                .transition(.opacity)
            }
            if !isMine { Spacer() }
        }
        .padding(.vertical, 1)
        .contentShape(Rectangle())
        .onTapGesture { onTap() }
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.15)) { isHovered = hovering }
        }
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
            if let date = message.createdAt {
                Text(date.formatted(.dateTime.hour().minute()))
                    .font(.caption)
            }
        }
        .foregroundStyle(.secondary)
    }
}
