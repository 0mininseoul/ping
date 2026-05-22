import SwiftUI
import AppKit

struct ReactionPickerView: View {
    let onPick: (String) -> Void
    let onMore: () -> Void

    static let quickSet = ["❤️", "👍", "👎", "😂", "‼️", "❓"]

    var body: some View {
        HStack(spacing: 8) {
            ForEach(Self.quickSet, id: \.self) { emoji in
                Button(action: { onPick(emoji) }) {
                    Text(emoji).font(.title3)
                }
                .buttonStyle(.plain)
            }
            Divider().frame(height: 18)
            Button(action: onMore) {
                Image(systemName: "plus")
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(.regularMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .shadow(radius: 4)
    }

    static func openSystemEmojiPicker() {
        NSApp.orderFrontCharacterPalette(nil)
    }
}
