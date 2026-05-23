import SwiftUI

struct MessageRowView: View {
    let message: VideoMessage
    let isMine: Bool
    let isExpanded: Bool
    let onTap: () -> Void
    let cacheService: HistoryCacheService
    @ObservedObject var inlineController: InlinePlayerController
    let archivePeerName: String
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
                    InlinePlayerView(
                        message: message,
                        isMine: isMine,
                        archivePeerName: archivePeerName,
                        cacheService: cacheService,
                        controller: inlineController
                    )
                } else {
                    thumbnail
                }
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
        thumbnailBase
        .overlay(
            Image(systemName: "play.fill")
                .font(.caption)
                .foregroundStyle(.white)
                .padding(6)
                .background(Circle().fill(Color.black.opacity(0.35)))
                .allowsHitTesting(false)
        )
    }

    @ViewBuilder
    private var thumbnailBase: some View {
        if message.captureMode == .faceOnly {
            thumbnailImage
                .frame(width: thumbnailSize.width, height: thumbnailSize.height)
                .clipShape(Circle())
        } else {
            thumbnailImage
                .frame(width: thumbnailSize.width, height: thumbnailSize.height)
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        }
    }

    private var thumbnailImage: some View {
        VideoThumbnailView(
            message: message,
            isMine: isMine,
            archivePeerName: archivePeerName,
            cacheService: cacheService,
            allowsRemoteFetch: false
        )
    }

    private var thumbnailSize: CGSize {
        if message.captureMode == .faceOnly {
            return CGSize(width: 60, height: 60)
        }

        return CGSize(width: 90, height: 90 / thumbnailAspectRatio)
    }

    private var thumbnailAspectRatio: CGFloat {
        CGFloat(max(0.5, min(3.0, message.aspectRatio ?? 1.78)))
    }
}
