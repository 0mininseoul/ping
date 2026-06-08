@preconcurrency import AVFoundation
import CoreGraphics
import Foundation

enum VideoCropper {
    static func cropToSquare(inputURL: URL) async throws -> URL {
        let asset = AVURLAsset(url: inputURL)
        guard let sourceVideoTrack = try await asset.loadTracks(withMediaType: .video).first else {
            return inputURL
        }

        let duration = try await asset.load(.duration)
        let naturalSize = try await sourceVideoTrack.load(.naturalSize)
        let preferredTransform = try await sourceVideoTrack.load(.preferredTransform)
        let transformedSize = naturalSize.applying(preferredTransform)
        let displaySize = CGSize(width: abs(transformedSize.width), height: abs(transformedSize.height))
        let side = min(displaySize.width, displaySize.height)
        guard side > 0 else { return inputURL }

        let composition = AVMutableComposition()
        guard let videoTrack = composition.addMutableTrack(
            withMediaType: .video,
            preferredTrackID: kCMPersistentTrackID_Invalid
        ) else {
            return inputURL
        }

        try videoTrack.insertTimeRange(
            CMTimeRange(start: .zero, duration: duration),
            of: sourceVideoTrack,
            at: .zero
        )

        if let sourceAudioTrack = try await asset.loadTracks(withMediaType: .audio).first,
           let audioTrack = composition.addMutableTrack(
            withMediaType: .audio,
            preferredTrackID: kCMPersistentTrackID_Invalid
           ) {
            try? audioTrack.insertTimeRange(
                CMTimeRange(start: .zero, duration: duration),
                of: sourceAudioTrack,
                at: .zero
            )
        }

        let videoComposition = AVMutableVideoComposition()
        videoComposition.renderSize = CGSize(width: side, height: side)
        videoComposition.frameDuration = frameDuration(for: sourceVideoTrack)

        let instruction = AVMutableVideoCompositionInstruction()
        instruction.timeRange = CMTimeRange(start: .zero, duration: duration)

        let layerInstruction = AVMutableVideoCompositionLayerInstruction(assetTrack: videoTrack)
        layerInstruction.setTransform(
            cropTransform(
                preferredTransform: preferredTransform,
                displaySize: displaySize,
                side: side
            ),
            at: .zero
        )
        instruction.layerInstructions = [layerInstruction]
        videoComposition.instructions = [instruction]

        let outputURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("ping-cropped-\(UUID().uuidString).mp4")

        guard let exporter = AVAssetExportSession(
            asset: composition,
            presetName: AVAssetExportPresetMediumQuality
        ) else {
            return inputURL
        }

        exporter.outputURL = outputURL
        exporter.outputFileType = .mp4
        exporter.shouldOptimizeForNetworkUse = true
        exporter.videoComposition = videoComposition

        try await export(exporter)
        return outputURL
    }

    private static func frameDuration(for track: AVAssetTrack) -> CMTime {
        let frameRate = track.nominalFrameRate
        guard frameRate > 0 else {
            return CMTime(value: 1, timescale: 30)
        }

        return CMTime(value: 1, timescale: CMTimeScale(max(1, Int32(frameRate.rounded()))))
    }

    private static func cropTransform(
        preferredTransform: CGAffineTransform,
        displaySize: CGSize,
        side: CGFloat
    ) -> CGAffineTransform {
        let xOffset = max((displaySize.width - side) / 2, 0)
        let yOffset = max((displaySize.height - side) / 2, 0)
        let centerCropTranslation = CGAffineTransform(translationX: -xOffset, y: -yOffset)
        return preferredTransform.concatenating(centerCropTranslation)
    }

    private static func export(_ exporter: AVAssetExportSession) async throws {
        try await withCheckedThrowingContinuation { continuation in
            exporter.exportAsynchronously {
                switch exporter.status {
                case .completed:
                    continuation.resume()
                case .failed:
                    continuation.resume(throwing: exporter.error ?? AVError(.exportFailed))
                case .cancelled:
                    continuation.resume(throwing: CancellationError())
                default:
                    continuation.resume(throwing: AVError(.exportFailed))
                }
            }
        }
    }
}
