import SwiftUI
import UIKit
import PingKit

actor ChatImageCache {
    static let shared = ChatImageCache()

    private var inflight: [String: Task<Data, Error>] = [:]
    private let diskDir: URL

    init() {
        let base = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        diskDir = base.appendingPathComponent("ping-chat-images", isDirectory: true)
        try? FileManager.default.createDirectory(at: diskDir, withIntermediateDirectories: true)
    }

    func data(for message: PingChatMessage) async throws -> Data {
        guard let mediaPath = message.mediaPath, !mediaPath.isEmpty else {
            throw PingKitError.unavailable
        }

        let url = diskDir.appendingPathComponent("\(message.id).\(message.mediaFileExtension)")
        if let cached = try? Data(contentsOf: url), !cached.isEmpty {
            return cached
        }
        if let existing = inflight[message.id] {
            return try await existing.value
        }

        let task = Task<Data, Error> {
            guard let client = await AppEnvironment.shared.makeClient() else {
                throw PingMobileError.notPaired
            }
            let data = try await client.downloadChatMedia(path: mediaPath)
            try data.write(to: url, options: .atomic)
            return data
        }
        inflight[message.id] = task
        defer { inflight[message.id] = nil }
        return try await task.value
    }
}

struct ChatImageAttachmentView: View {
    let message: PingChatMessage

    @State private var image: UIImage?
    @State private var didFail = false

    private let maxWidth: CGFloat = 240
    private let maxHeight: CGFloat = 260

    var body: some View {
        ZStack {
            if let image {
                Image(uiImage: image)
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
                .strokeBorder(Color.primary.opacity(0.06))
        )
        .accessibilityLabel(accessibilityLabel)
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

    private var accessibilityLabel: String {
        guard let fileName = message.mediaFileName,
              !fileName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return "사진"
        }
        return fileName
    }

    @MainActor
    private func loadImage() async {
        guard image == nil else { return }
        do {
            let data = try await ChatImageCache.shared.data(for: message)
            image = UIImage(data: data)
            didFail = image == nil
        } catch {
            didFail = true
        }
    }
}
