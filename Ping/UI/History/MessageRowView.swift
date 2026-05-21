import SwiftUI
import AVKit

struct MessageRowView: View {
    let message: VideoMessage
    let isMine: Bool
    let isExpanded: Bool
    let onTap: () -> Void
    let cacheService: HistoryCacheService
    @ObservedObject var inlineController: InlinePlayerController
    let onSave: () -> Void
    let onDelete: () -> Void

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
            }
            if isHovered && !isExpanded {
                HStack(spacing: 8) {
                    Button(action: onSave) {
                        Image(systemName: "arrow.down.circle").imageScale(.small)
                    }.buttonStyle(.plain)
                    Button(action: onDelete) {
                        Image(systemName: "trash").imageScale(.small)
                    }.buttonStyle(.plain)
                }
                .transition(.opacity)
            }
            if !isMine { Spacer() }
        }
        .padding(.vertical, 4)
        .contentShape(Rectangle())
        .onTapGesture { onTap() }
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.15)) { isHovered = hovering }
        }
    }

    private var thumbnail: some View {
        Group {
            if message.captureMode == .faceOnly {
                Circle().fill(Color.gray.opacity(0.3)).frame(width: 60, height: 60)
            } else {
                RoundedRectangle(cornerRadius: 8).fill(Color.gray.opacity(0.3))
                    .aspectRatio(message.aspectRatio ?? 1.78, contentMode: .fit)
                    .frame(maxWidth: 90)
            }
        }
        .overlay(Image(systemName: "play.fill").foregroundStyle(.white))
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
