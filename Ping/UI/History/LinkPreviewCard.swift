import SwiftUI
import AppKit

struct LinkPreviewCard: View {
    let url: URL
    let isMine: Bool

    @State private var metadata: LinkPreviewMetadata
    private let cardWidth: CGFloat = 280
    private let previewImageHeight: CGFloat = 168

    init(url: URL, isMine: Bool) {
        self.url = url
        self.isMine = isMine
        _metadata = State(initialValue: .fallback(url: url))
    }

    var body: some View {
        Button {
            NSWorkspace.shared.open(url)
        } label: {
            VStack(alignment: .leading, spacing: 0) {
                previewImage
                    .frame(width: cardWidth, height: previewImageHeight)
                    .clipped()

                metadataText
                    .padding(.horizontal, 12)
                    .padding(.vertical, 11)
            }
            .frame(width: cardWidth, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(Color(nsColor: .textBackgroundColor))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .strokeBorder(Color.black.opacity(0.08))
            )
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
        .buttonStyle(.plain)
        .task(id: url) {
            metadata = await LinkPreviewCache.shared.metadata(for: url)
        }
        .accessibilityLabel(Text(metadata.displayTitle))
    }

    private var metadataText: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(metadata.displayTitle)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(.primary)
                .lineLimit(2)
            if let summary = metadata.summary, !summary.isEmpty {
                Text(summary)
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
            Text(LinkPreviewDetector.displayHost(for: url))
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(Color.accentColor)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
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
        } else {
            placeholder
        }
    }

    private var placeholder: some View {
        Rectangle()
            .fill(Color(nsColor: .controlBackgroundColor))
            .overlay(
                Image(systemName: "link")
                    .font(.system(size: 30, weight: .semibold))
                    .foregroundStyle(.secondary)
            )
    }
}
