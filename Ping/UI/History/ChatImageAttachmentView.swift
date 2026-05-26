import AppKit
import SwiftUI

struct ChatImageAttachmentView: View {
    let message: ChatMessage
    let cacheService: HistoryCacheService

    @State private var image: NSImage?
    @State private var didFail = false
    @State private var isPreviewPresented = false

    private let maxWidth: CGFloat = 240
    private let maxHeight: CGFloat = 260

    var body: some View {
        ZStack {
            if let image {
                Image(nsImage: image)
                    .resizable()
                    .scaledToFit()
                    .frame(width: displaySize.width, height: displaySize.height)
            } else if didFail {
                VStack(spacing: 6) {
                    Image(systemName: "photo")
                        .font(.title3)
                    Text("사진을 불러올 수 없음")
                        .font(.caption)
                }
                .foregroundStyle(.secondary)
            } else {
                ProgressView()
                    .controlSize(.small)
            }
        }
        .frame(width: displaySize.width, height: displaySize.height)
        .background(Color.gray.opacity(0.10))
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(Color.white.opacity(0.12), lineWidth: 0.5)
        )
        .contentShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .onTapGesture {
            guard image != nil else { return }
            isPreviewPresented = true
        }
        .popover(isPresented: $isPreviewPresented) {
            if let image {
                ChatImagePreviewPopover(image: image, fileName: message.mediaFileName)
            }
        }
        .task(id: message.mediaPath) {
            await loadImage()
        }
    }

    private var displaySize: CGSize {
        guard let width = message.mediaWidth,
              let height = message.mediaHeight,
              width > 0,
              height > 0 else {
            return CGSize(width: 200, height: 160)
        }

        let scale = min(maxWidth / CGFloat(width), maxHeight / CGFloat(height))
        return CGSize(
            width: max(80, CGFloat(width) * scale),
            height: max(80, CGFloat(height) * scale)
        )
    }

    @MainActor
    private func loadImage() async {
        guard image == nil,
              let mediaPath = message.mediaPath,
              let messageId = message.id else {
            return
        }

        let fileExtension = message.mediaFileExtension
        if let cached = cacheService.cachedAttachmentFile(
            roomId: message.roomId,
            messageId: messageId,
            fileExtension: fileExtension
        ), let cachedImage = NSImage(contentsOf: cached) {
            image = cachedImage
            didFail = false
            return
        }

        do {
            let tempURL = try await StorageService().downloadChatMedia(
                remotePath: mediaPath,
                fileExtension: fileExtension
            )
            let cachedURL = try cacheService.storeAttachmentDownload(
                roomId: message.roomId,
                messageId: messageId,
                fileExtension: fileExtension,
                sourceTemp: tempURL
            )
            image = NSImage(contentsOf: cachedURL)
            didFail = image == nil
        } catch {
            didFail = true
        }
    }
}

private struct ChatImagePreviewPopover: View {
    let image: NSImage
    let fileName: String?

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                Text(displayName)
                    .font(.callout.weight(.semibold))
                    .lineLimit(1)

                Spacer()

                Button {
                    dismiss()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 16, weight: .semibold))
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
                .help("닫기")
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)

            Divider()

            Image(nsImage: image)
                .resizable()
                .scaledToFit()
                .frame(maxWidth: 780, maxHeight: 620)
                .padding(14)
        }
        .frame(minWidth: 360, minHeight: 260)
        .background(.regularMaterial)
    }

    private var displayName: String {
        guard let fileName,
              !fileName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return "사진"
        }
        return fileName
    }
}
