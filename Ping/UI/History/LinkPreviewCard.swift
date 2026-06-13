import SwiftUI
import AppKit

struct LinkPreviewCard: View {
    let url: URL
    let isMine: Bool

    @State private var metadata: LinkPreviewMetadata

    init(url: URL, isMine: Bool) {
        self.url = url
        self.isMine = isMine
        _metadata = State(initialValue: .fallback(url: url))
    }

    var body: some View {
        Button {
            NSWorkspace.shared.open(url)
        } label: {
            HStack(spacing: 8) {
                previewImage
                VStack(alignment: .leading, spacing: 3) {
                    Text(metadata.displayTitle)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(isMine ? .white : .primary)
                        .lineLimit(2)
                    if let summary = metadata.summary, !summary.isEmpty {
                        Text(summary)
                            .font(.caption2)
                            .foregroundStyle(isMine ? .white.opacity(0.78) : .secondary)
                            .lineLimit(2)
                    }
                    Text(LinkPreviewDetector.displayHost(for: url))
                        .font(.caption2.weight(.medium))
                        .foregroundStyle(isMine ? .white.opacity(0.70) : .secondary)
                        .lineLimit(1)
                }
                Spacer(minLength: 0)
            }
            .padding(8)
            .frame(maxWidth: 280, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(isMine ? Color.white.opacity(0.16) : Color.gray.opacity(0.13))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(isMine ? Color.white.opacity(0.20) : Color.black.opacity(0.06))
            )
        }
        .buttonStyle(.plain)
        .task(id: url) {
            metadata = await LinkPreviewCache.shared.metadata(for: url)
        }
        .accessibilityLabel(Text(metadata.displayTitle))
    }

    @ViewBuilder
    private var previewImage: some View {
        if let imageURL = metadata.imageURL {
            AsyncImage(url: imageURL) { phase in
                switch phase {
                case .success(let image):
                    image
                        .resizable()
                        .scaledToFill()
                default:
                    placeholder
                }
            }
            .frame(width: 54, height: 54)
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        } else {
            placeholder
                .frame(width: 54, height: 54)
        }
    }

    private var placeholder: some View {
        RoundedRectangle(cornerRadius: 8, style: .continuous)
            .fill(isMine ? Color.white.opacity(0.14) : Color.gray.opacity(0.20))
            .overlay(
                Image(systemName: "link")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(isMine ? .white.opacity(0.80) : .secondary)
            )
    }
}
