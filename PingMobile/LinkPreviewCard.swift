import SwiftUI
import PingKit

struct LinkPreviewCard: View {
    let url: URL
    let mine: Bool

    @Environment(\.openURL) private var openURL
    @State private var metadata: PingLinkPreviewMetadata

    init(url: URL, mine: Bool) {
        self.url = url
        self.mine = mine
        _metadata = State(initialValue: .fallback(url: url))
    }

    var body: some View {
        Button {
            openURL(url)
        } label: {
            HStack(spacing: 9) {
                previewImage
                VStack(alignment: .leading, spacing: 3) {
                    Text(metadata.displayTitle)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(mine ? .white : Color(uiColor: .label))
                        .lineLimit(2)
                    if let summary = metadata.summary, !summary.isEmpty {
                        Text(summary)
                            .font(.caption2)
                            .foregroundStyle(mine ? .white.opacity(0.78) : .secondary)
                            .lineLimit(2)
                    }
                    Text(PingLinkPreviewDetector.displayHost(for: url))
                        .font(.caption2.weight(.medium))
                        .foregroundStyle(mine ? .white.opacity(0.70) : .secondary)
                        .lineLimit(1)
                }
                Spacer(minLength: 0)
            }
            .padding(8)
            .frame(maxWidth: 260, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 13, style: .continuous)
                    .fill(mine ? Color.white.opacity(0.16) : Color.gray.opacity(0.13))
            )
        }
        .buttonStyle(.plain)
        .task(id: url) {
            metadata = await PingLinkPreviewCache.shared.metadata(for: url)
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
            .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
        } else {
            placeholder
                .frame(width: 54, height: 54)
        }
    }

    private var placeholder: some View {
        RoundedRectangle(cornerRadius: 9, style: .continuous)
            .fill(mine ? Color.white.opacity(0.14) : Color.gray.opacity(0.20))
            .overlay(
                Image(systemName: "link")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(mine ? .white.opacity(0.80) : .secondary)
            )
    }
}
