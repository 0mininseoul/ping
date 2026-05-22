import SwiftUI

struct ChatMessageRowView: View {
    let message: ChatMessage
    let isMine: Bool
    let showsSender: Bool
    let replyPreview: ReplyPreview?
    let reactions: [HistoryViewModel.ReactionAggregate]
    let onReply: () -> Void
    let onReact: () -> Void
    let onDelete: () -> Void
    let onToggleReaction: (String) -> Void

    @State private var isHovered: Bool = false

    enum ReplyPreview {
        case chat(sender: String, body: String)
        case video(sender: String, captureMode: CaptureMode)

        var senderName: String {
            switch self {
            case .chat(let s, _): return s
            case .video(let s, _): return s
            }
        }
    }

    var body: some View {
        HStack(alignment: .bottom, spacing: 6) {
            if isMine {
                Spacer(minLength: 40)
                timeLabel.foregroundStyle(.tertiary)
            }

            if !isMine && isHovered { hoverActions }

            VStack(alignment: isMine ? .trailing : .leading, spacing: 2) {
                if showsSender && !isMine {
                    Text(message.senderNickname)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 4)
                }
                if let replyPreview {
                    replyQuote(replyPreview)
                }
                bubble
                if !reactions.isEmpty {
                    reactionStrip
                }
            }
            .frame(maxWidth: 360, alignment: isMine ? .trailing : .leading)

            if !isMine {
                timeLabel.foregroundStyle(.tertiary)
            }
            if isMine && isHovered { hoverActions }
            if !isMine { Spacer(minLength: 40) }
        }
        .padding(.vertical, 1)
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.12)) { isHovered = hovering }
        }
    }

    @ViewBuilder
    private var timeLabel: some View {
        if let date = message.createdAt {
            Text(date.formatted(.dateTime.hour().minute()))
                .font(.caption2)
                .opacity(0.6)
        }
    }

    private var bubble: some View {
        Text(message.body)
            .font(.body)
            .foregroundStyle(isMine ? .white : Color.primary)
            .padding(.horizontal, 11)
            .padding(.vertical, 6)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(isMine ? Color.accentColor : Color.gray.opacity(0.18))
            )
            .textSelection(.enabled)
    }

    @ViewBuilder
    private func replyQuote(_ preview: ReplyPreview) -> some View {
        let text: String = {
            switch preview {
            case .chat(_, let body):
                return String(body.prefix(60)) + (body.count > 60 ? "…" : "")
            case .video(_, let mode):
                return mode == .faceOnly ? "🎥 얼굴 영상" : "🖥 화면+얼굴 영상"
            }
        }()
        HStack(spacing: 4) {
            Rectangle()
                .fill(Color.secondary.opacity(0.4))
                .frame(width: 2)
            VStack(alignment: .leading, spacing: 2) {
                Text(preview.senderName)
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.secondary)
                Text(text)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(Color.gray.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    private var reactionStrip: some View {
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

    private var hoverActions: some View {
        HStack(spacing: 6) {
            Button(action: onReply) {
                Image(systemName: "arrowshape.turn.up.left").imageScale(.small)
            }.buttonStyle(.plain)
            Button(action: onReact) {
                Image(systemName: "face.smiling").imageScale(.small)
            }.buttonStyle(.plain)
            if isMine {
                Button(action: onDelete) {
                    Image(systemName: "trash").imageScale(.small)
                }.buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 4)
        .foregroundStyle(.secondary)
    }
}
