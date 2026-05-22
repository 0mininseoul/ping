import SwiftUI

struct ChatComposerView: View {
    @Binding var draft: String
    let replyTarget: HistoryViewModel.ReplyTarget?
    let onCancelReply: () -> Void
    let onSend: () -> Void

    var body: some View {
        VStack(spacing: 6) {
            if let replyTarget {
                HStack {
                    Image(systemName: "arrowshape.turn.up.left.fill")
                        .foregroundStyle(.secondary)
                    Text(replyPreviewText(replyTarget))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                    Spacer()
                    Button(action: onCancelReply) {
                        Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary)
                    }.buttonStyle(.plain)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 4)
                .background(Color.gray.opacity(0.08))
            }
            HStack(alignment: .bottom, spacing: 8) {
                TextEditor(text: $draft)
                    .font(.body)
                    .frame(minHeight: 32, maxHeight: 132)
                    .scrollContentBackground(.hidden)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 6)
                    .background(Color.gray.opacity(0.06))
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                Button(action: onSend) {
                    Image(systemName: "paperplane.fill")
                        .padding(8)
                        .background(canSend ? Color.accentColor : Color.gray.opacity(0.3))
                        .foregroundStyle(.white)
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
