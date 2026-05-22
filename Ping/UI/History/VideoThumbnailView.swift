import SwiftUI
import AVFoundation
import AppKit

struct VideoThumbnailView: View {
    let message: VideoMessage
    let cacheService: HistoryCacheService

    @State private var thumbnail: NSImage?
    @State private var hasFailed: Bool = false

    var body: some View {
        Group {
            if let thumbnail {
                Image(nsImage: thumbnail)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
            } else if hasFailed {
                placeholderView(color: Color.gray.opacity(0.18))
                    .overlay(
                        Image(systemName: "exclamationmark.triangle")
                            .foregroundStyle(.secondary)
                    )
            } else {
                placeholderView(color: Color.gray.opacity(0.3))
                    .overlay(ProgressView().scaleEffect(0.6))
            }
        }
        .task(id: message.id) { await load() }
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

        // 1) Try cache first
        if let cached = cacheService.cachedFile(roomId: message.roomId, messageId: id) {
            thumbnail = await extractFrame(from: cached)
            if thumbnail == nil { hasFailed = true }
            return
        }

        // 2) Download — gracefully handle 404
        do {
            let storage = StorageService()
            let temp = try await storage.downloadVideo(remotePath: message.videoUrl)
            let local = try cacheService.storeDownload(roomId: message.roomId, messageId: id, sourceTemp: temp)
            thumbnail = await extractFrame(from: local)
            if thumbnail == nil { hasFailed = true }
        } catch {
            NSLog("VideoThumbnailView: download failed for \(id): \(error)")
            hasFailed = true
        }
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
}
