import SwiftUI
import AppKit

struct ChatMessageRowView: View {
    let message: ChatMessage
    let isMine: Bool
    let showsSender: Bool
    let replyPreview: ReplyPreview?
    let cacheService: HistoryCacheService
    let reactions: [HistoryViewModel.ReactionAggregate]
    let onReply: () -> Void
    let onReact: () -> Void
    let onDelete: () -> Void
    let onToggleReaction: (String) -> Void

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
            if isMine { Spacer(minLength: 40) }

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
            .frame(maxWidth: messageMaxWidth, alignment: isMine ? .trailing : .leading)

            if !isMine { Spacer(minLength: 40) }
        }
        .frame(maxWidth: .infinity, alignment: isMine ? .trailing : .leading)
        .padding(.vertical, 1)
    }

    private var bubble: some View {
        VStack(alignment: isMine ? .trailing : .leading, spacing: 6) {
            if message.hasImageAttachment {
                ChatImageAttachmentView(message: message, cacheService: cacheService)
                    .contextMenu {
                        Button("답장", action: onReply)
                        Button("이모지 반응", action: onReact)
                        if isMine {
                            Divider()
                            Button("삭제", action: onDelete)
                        }
                    }
            }

            if !message.body.isEmpty {
                let textSize = ChatMessageBubbleLayout.textContentSize(
                    for: message.body,
                    font: messageFont
                )
                let bubbleSize = ChatMessageBubbleLayout.textBubbleSize(
                    for: message.body,
                    font: messageFont
                )
                SelectableTextView(
                    text: message.body,
                    font: messageFont,
                    textColor: isMine ? .white : NSColor.labelColor,
                    maxWidth: textContentMaxWidth,
                    menuProvider: { makeContextMenu() }
                )
                .frame(width: textSize.width, height: textSize.height, alignment: .leading)
                .padding(.horizontal, textBubbleHorizontalPadding)
                .padding(.vertical, ChatMessageBubbleLayout.textBubbleVerticalPadding)
                .frame(width: bubbleSize.width, height: bubbleSize.height, alignment: .leading)
                .background(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(isMine ? Color.accentColor : Color.gray.opacity(0.18))
                )
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            }

            if let url = LinkPreviewDetector.firstURL(in: message.body) {
                LinkPreviewCard(url: url, isMine: isMine)
                    .contextMenu {
                        Button("링크 열기") {
                            NSWorkspace.shared.open(url)
                        }
                        Button("답장", action: onReply)
                        Button("이모지 반응", action: onReact)
                        if isMine {
                            Divider()
                            Button("삭제", action: onDelete)
                        }
                    }
            }
        }
        .padding(.trailing, isMine ? ChatMessageBubbleLayout.outgoingContentTrailingInset : 0)
    }

    private var messageMaxWidth: CGFloat {
        ChatMessageBubbleLayout.messageMaxWidth
    }

    private var textBubbleHorizontalPadding: CGFloat {
        ChatMessageBubbleLayout.textBubbleHorizontalPadding
    }

    private var textContentMaxWidth: CGFloat {
        ChatMessageBubbleLayout.textContentMaxWidth
    }

    private var messageFont: NSFont {
        NSFont.systemFont(ofSize: NSFont.systemFontSize)
    }

    private func makeContextMenu() -> NSMenu {
        let menu = NSMenu()

        let copyItem = NSMenuItem(title: "복사", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        menu.addItem(copyItem)

        menu.addItem(.separator())

        let replyItem = NSMenuItem(title: "답장", action: #selector(ContextMenuTarget.handle(_:)), keyEquivalent: "")
        replyItem.target = ContextMenuTarget.shared
        replyItem.representedObject = ContextMenuAction(action: onReply)
        menu.addItem(replyItem)

        let reactItem = NSMenuItem(title: "이모지 반응", action: #selector(ContextMenuTarget.handle(_:)), keyEquivalent: "")
        reactItem.target = ContextMenuTarget.shared
        reactItem.representedObject = ContextMenuAction(action: onReact)
        menu.addItem(reactItem)

        if isMine {
            menu.addItem(.separator())
            let deleteItem = NSMenuItem(title: "삭제", action: #selector(ContextMenuTarget.handle(_:)), keyEquivalent: "")
            deleteItem.target = ContextMenuTarget.shared
            deleteItem.representedObject = ContextMenuAction(action: onDelete)
            menu.addItem(deleteItem)
        }

        return menu
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

}

enum ChatMessageBubbleLayout {
    static let messageMaxWidth: CGFloat = 280
    static let textBubbleHorizontalPadding: CGFloat = 11
    static let textBubbleVerticalPadding: CGFloat = 6
    static let outgoingContentTrailingInset: CGFloat = 28

    static var textContentMaxWidth: CGFloat {
        messageMaxWidth - textBubbleHorizontalPadding * 2
    }

    static func textContentSize(for text: String, font: NSFont) -> CGSize {
        SelectableTextLayout.size(
            text: text,
            font: font,
            maxWidth: textContentMaxWidth,
            proposedWidth: textContentMaxWidth
        )
    }

    static func textBubbleSize(for text: String, font: NSFont) -> CGSize {
        let textSize = textContentSize(for: text, font: font)
        return CGSize(
            width: textSize.width + textBubbleHorizontalPadding * 2,
            height: textSize.height + textBubbleVerticalPadding * 2
        )
    }
}
