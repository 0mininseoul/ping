import SwiftUI
import PingKit

struct LinkPreviewCard: View {
    let url: URL
    let mine: Bool

    @Environment(\.openURL) private var openURL
    @State private var metadata: PingLinkPreviewMetadata
    private let maxCardWidth: CGFloat = 320
    private let horizontalSafetyInset: CGFloat = 88
    private let previewImageHeight: CGFloat = 190

    private var cardWidth: CGFloat {
        min(maxCardWidth, max(240, UIScreen.main.bounds.width - horizontalSafetyInset))
    }

    init(url: URL, mine: Bool) {
        self.url = url
        self.mine = mine
        _metadata = State(initialValue: .fallback(url: url))
    }

    var body: some View {
        Button {
            openURL(url)
        } label: {
            VStack(alignment: .leading, spacing: 0) {
                previewImage
                    .frame(width: cardWidth, height: previewImageHeight)
                    .clipped()

                metadataText
                    .padding(.horizontal, 14)
                    .padding(.vertical, 12)
            }
            .frame(width: cardWidth, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(Color(uiColor: .systemBackground))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .strokeBorder(Color.black.opacity(0.06))
            )
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
        .buttonStyle(.plain)
        .task(id: url) {
            metadata = await PingLinkPreviewCache.shared.metadata(for: url)
        }
        .accessibilityLabel(Text(metadata.displayTitle))
    }

    private var metadataText: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(metadata.displayTitle)
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(Color(uiColor: .label))
                .lineLimit(2)
            if let summary = metadata.summary, !summary.isEmpty {
                Text(summary)
                    .font(.system(size: 14))
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
            Text(PingLinkPreviewDetector.displayHost(for: url))
                .font(.system(size: 14, weight: .medium))
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
            .fill(Color(uiColor: .secondarySystemBackground))
            .overlay(
                Image(systemName: "link")
                    .font(.system(size: 34, weight: .semibold))
                    .foregroundStyle(.secondary)
            )
    }
}
