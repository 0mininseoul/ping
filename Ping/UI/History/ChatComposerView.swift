import SwiftUI
import AppKit

struct ChatComposerView: View {
    @Binding var draft: String
    let replyTarget: HistoryViewModel.ReplyTarget?
    let onCancelReply: () -> Void
    let onSend: () -> Void

    @State private var calculatedHeight: CGFloat = 36

    private let minHeight: CGFloat = 36
    private let maxHeight: CGFloat = 120

    var body: some View {
        VStack(spacing: 0) {
            if let replyTarget {
                HStack(spacing: 6) {
                    Image(systemName: "arrowshape.turn.up.left.fill")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    Text(replyPreviewText(replyTarget))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                    Spacer()
                    Button(action: onCancelReply) {
                        Image(systemName: "xmark.circle.fill")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(Color(NSColor.controlBackgroundColor).opacity(0.6))
            }

            HStack(alignment: .bottom, spacing: 8) {
                ZStack(alignment: .topLeading) {
                    if draft.isEmpty {
                        Text("메시지 입력…")
                            .font(.body)
                            .foregroundStyle(.tertiary)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 8)
                            .allowsHitTesting(false)
                    }
                    ComposerTextEditor(
                        text: $draft,
                        calculatedHeight: $calculatedHeight,
                        minHeight: minHeight,
                        maxHeight: maxHeight
                    )
                }
                .frame(height: max(minHeight, min(calculatedHeight, maxHeight)))
                .background(Color.gray.opacity(0.08))
                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .strokeBorder(Color.gray.opacity(0.18), lineWidth: 0.5)
                )

                Button(action: onSend) {
                    Image(systemName: "paperplane.fill")
                        .font(.body)
                        .foregroundStyle(canSend ? .white : .secondary)
                        .frame(width: 30, height: 30)
                        .background(canSend ? Color.accentColor : Color.gray.opacity(0.18))
                        .clipShape(Circle())
                }
                .buttonStyle(.plain)
                .disabled(!canSend)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
        }
        .background(.regularMaterial)
    }

    private var canSend: Bool {
        !draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && draft.count <= 2000
    }

    private func replyPreviewText(_ target: HistoryViewModel.ReplyTarget) -> String {
        switch target {
        case .chat(_, let sender, let preview):
            return "\(sender): \(preview)"
        case .video(_, let sender, let mode):
            let label = mode == .faceOnly ? "얼굴 영상" : "화면+얼굴 영상"
            return "\(sender): \(label)"
        }
    }
}

/// NSTextView wrapper with explicit textContainerInset matching placeholder padding.
/// Padding 10 horizontal / 6 vertical → cursor aligns with the placeholder Text view.
private struct ComposerTextEditor: NSViewRepresentable {
    @Binding var text: String
    @Binding var calculatedHeight: CGFloat
    let minHeight: CGFloat
    let maxHeight: CGFloat

    func makeNSView(context: Context) -> NSScrollView {
        let scroll = NSTextView.scrollableTextView()
        scroll.drawsBackground = false
        scroll.hasVerticalScroller = true
        scroll.autohidesScrollers = true
        scroll.borderType = .noBorder

        let textView = scroll.documentView as! NSTextView
        textView.drawsBackground = false
        textView.isRichText = false
        textView.isEditable = true
        textView.allowsUndo = true
        textView.font = NSFont.systemFont(ofSize: NSFont.systemFontSize)
        textView.textContainerInset = NSSize(width: 10, height: 8)
        textView.delegate = context.coordinator
        textView.textContainer?.lineFragmentPadding = 0
        textView.string = text

        return scroll
    }

    func updateNSView(_ scroll: NSScrollView, context: Context) {
        guard let textView = scroll.documentView as? NSTextView else { return }
        if textView.string != text {
            let selected = textView.selectedRange()
            textView.string = text
            textView.setSelectedRange(selected)
        }
        Task { @MainActor in
            recalculateHeight(textView: textView)
        }
    }

    @MainActor
    private func recalculateHeight(textView: NSTextView) {
        guard let layoutManager = textView.layoutManager,
              let textContainer = textView.textContainer else { return }
        layoutManager.ensureLayout(for: textContainer)
        let used = layoutManager.usedRect(for: textContainer)
        let inset = textView.textContainerInset
        let target = used.height + inset.height * 2
        let clamped = max(minHeight, min(target, maxHeight))
        if abs(calculatedHeight - clamped) > 0.5 {
            calculatedHeight = clamped
        }
    }

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    final class Coordinator: NSObject, NSTextViewDelegate {
        var parent: ComposerTextEditor
        init(_ parent: ComposerTextEditor) { self.parent = parent }

        func textDidChange(_ notification: Notification) {
            guard let textView = notification.object as? NSTextView else { return }
            parent.text = textView.string
            Task { @MainActor in
                parent.recalculateHeight(textView: textView)
            }
        }
    }
}
