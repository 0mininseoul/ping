import SwiftUI
import AVFoundation
import AppKit

struct VideoThumbnailView: View {
    let message: VideoMessage
    let isMine: Bool
    let archivePeerName: String
    let cacheService: HistoryCacheService
    let allowsRemoteFetch: Bool

    @State private var thumbnail: NSImage?
    @State private var hasFailed: Bool = false
    @State private var isLocalOnlyMiss: Bool = false

    var body: some View {
        Group {
            if let thumbnail {
                Image(nsImage: thumbnail)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
            } else if hasFailed {
                placeholderView(color: Color.gray.opacity(0.18))
                    .overlay(failureOverlay)
            } else {
                placeholderView(color: Color.gray.opacity(0.3))
                    .overlay {
                        if allowsRemoteFetch {
                            ProgressView().scaleEffect(0.6)
                        }
                    }
            }
        }
        .task(id: message.id) { await load() }
    }

    @ViewBuilder
    private var failureOverlay: some View {
        if !isLocalOnlyMiss {
            Image(systemName: "exclamationmark.triangle")
                .foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private func placeholderView(color: Color) -> some View {
        Group {
            if message.captureMode == .faceOnly {
                Circle().fill(color)
            } else {
                RoundedRectangle(cornerRadius: 8, style: .continuous).fill(color)
            }
        }
    }

    private func load() async {
        guard let id = message.id else { hasFailed = true; return }

        if let thumbnailURL = cacheService.cachedThumbnail(roomId: message.roomId, messageId: id),
           let cachedThumbnail = NSImage(contentsOf: thumbnailURL) {
            thumbnail = cachedThumbnail
            return
        }

        // 1) Try video cache first
        if let cached = cacheService.cachedFile(roomId: message.roomId, messageId: id) {
            await loadThumbnail(from: cached, roomId: message.roomId, messageId: id)
            return
        }
        if let archived = archivedVideoURL() {
            await loadThumbnail(from: archived, roomId: message.roomId, messageId: id)
            return
        }

        guard allowsRemoteFetch else {
            isLocalOnlyMiss = true
            hasFailed = true
            return
        }

        // 2) Download — gracefully handle 404
        do {
            let storage = StorageService()
            let temp = try await storage.downloadVideo(remotePath: message.videoUrl)
            let local = try cacheService.storeDownload(roomId: message.roomId, messageId: id, sourceTemp: temp)
            await loadThumbnail(from: local, roomId: message.roomId, messageId: id)
        } catch {
            NSLog("VideoThumbnailView: download failed for \(id): \(error)")
            hasFailed = true
        }
    }

    private func loadThumbnail(from url: URL, roomId: String, messageId: String) async {
        guard let extracted = await extractFrame(from: url) else {
            hasFailed = true
            return
        }

        _ = try? cacheService.storeThumbnail(extracted, roomId: roomId, messageId: messageId)
        thumbnail = extracted
    }

    private func extractFrame(from url: URL) async -> NSImage? {
        let asset = AVURLAsset(url: url)
        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        generator.maximumSize = CGSize(width: 240, height: 240)
        do {
            let cgImage: CGImage
            if #available(macOS 13.0, *) {
                cgImage = try await generator.image(at: CMTime(seconds: 0.5, preferredTimescale: 600)).image
            } else {
                cgImage = try generator.copyCGImage(at: CMTime(seconds: 0.5, preferredTimescale: 600), actualTime: nil)
            }
            return NSImage(cgImage: cgImage, size: CGSize(width: cgImage.width, height: cgImage.height))
        } catch {
            NSLog("VideoThumbnailView: frame extract failed: \(error)")
            return nil
        }
    }

    private func archivedVideoURL() -> URL? {
        guard let createdAt = message.createdAt else { return nil }
        guard isMine || message.allowsLocalSave else { return nil }
        let direction: LocalArchive.Direction = isMine ? .sent : .received
        return LocalArchive.existingVideoURL(
            direction: direction,
            nickname: archivePeerName,
            date: createdAt
        )
    }
}
