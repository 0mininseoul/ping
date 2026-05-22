import SwiftUI

struct ChatComposerView: View {
    @Binding var draft: String
    let replyTarget: HistoryViewModel.ReplyTarget?
    let onCancelReply: () -> Void
    let onSend: () -> Void

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
                            .padding(.horizontal, 12)
                            .padding(.vertical, 8)
                            .allowsHitTesting(false)
                    }
                    TextEditor(text: $draft)
                        .font(.body)
                        .scrollContentBackground(.hidden)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .frame(minHeight: 32, maxHeight: 96)
                }
                .background(Color.gray.opacity(0.08))
                .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .strokeBorder(Color.gray.opacity(0.18), lineWidth: 0.5)
                )

                Button(action: onSend) {
                    Image(systemName: "paperplane.fill")
                        .font(.body)
                        .foregroundStyle(canSend ? .white : .secondary)
                        .frame(width: 32, height: 32)
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
