@preconcurrency import AVFoundation
@preconcurrency import ScreenCaptureKit
import CoreImage
import CoreVideo

@MainActor
final class ScreenFaceRecorder: NSObject {
    struct Output {
        let url: URL
        let aspectRatio: Double
    }

    func record(
        screenManager: ScreenCaptureManager,
        cameraSession: AVCaptureSession,
        screenSize: CGSize,
        duration: TimeInterval = 3.0
    ) async throws -> Output {
        let outputURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("ping-sf-\(UUID().uuidString).mp4")
        try? FileManager.default.removeItem(at: outputURL)

        let longSide: CGFloat = 720
        let scale = longSide / max(screenSize.width, screenSize.height)
        let outW = Int((screenSize.width * scale).rounded())
        let outH = Int((screenSize.height * scale).rounded())
        let outputSize = CGSize(width: outW, height: outH)

        let writer = try AVAssetWriter(outputURL: outputURL, fileType: .mp4)

        let videoSettings: [String: Any] = [
            AVVideoCodecKey: AVVideoCodecType.h264,
            AVVideoWidthKey: outW,
            AVVideoHeightKey: outH,
            AVVideoCompressionPropertiesKey: [
                AVVideoAverageBitRateKey: 4_000_000,
                AVVideoExpectedSourceFrameRateKey: 30,
                AVVideoMaxKeyFrameIntervalKey: 30
            ]
        ]

        let writerInput = AVAssetWriterInput(mediaType: .video, outputSettings: videoSettings)
        writerInput.expectsMediaDataInRealTime = true

        let adaptor = AVAssetWriterInputPixelBufferAdaptor(
            assetWriterInput: writerInput,
            sourcePixelBufferAttributes: [
                kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
                kCVPixelBufferWidthKey as String: outW,
                kCVPixelBufferHeightKey as String: outH
            ]
        )

        writer.add(writerInput)
        writer.startWriting()
        writer.startSession(atSourceTime: .zero)

        let ciContext = CIContext()
        let start = Date()
        let frameInterval: TimeInterval = 1.0 / 30.0
        var frameIndex: Int64 = 0

        while Date().timeIntervalSince(start) < duration {
            while !writerInput.isReadyForMoreMediaData {
                try? await Task.sleep(for: .milliseconds(5))
            }

            guard let screenImage = screenManager.latestFrame else {
                try? await Task.sleep(for: .milliseconds(10))
                continue
            }
            guard let cameraImage = CameraManager.latestVideoFrame else {
                try? await Task.sleep(for: .milliseconds(10))
                continue
            }

            let sx = outputSize.width / screenImage.extent.width
            let sy = outputSize.height / screenImage.extent.height
            let scaledScreen = screenImage.transformed(by: CGAffineTransform(scaleX: sx, y: sy))
            let composed = PIPCompositor.compose(
                screen: scaledScreen,
                face: cameraImage,
                outputSize: outputSize,
                faceDiameterRatio: ScreenFaceLayout.faceDiameterRatio,
                paddingRatio: ScreenFaceLayout.paddingRatio
            )

            var pbOpt: CVPixelBuffer?
            CVPixelBufferCreate(nil, outW, outH, kCVPixelFormatType_32BGRA, [
                kCVPixelBufferCGImageCompatibilityKey: true,
                kCVPixelBufferCGBitmapContextCompatibilityKey: true
            ] as CFDictionary, &pbOpt)
            guard let pb = pbOpt else { continue }
            ciContext.render(composed, to: pb)

            let presentation = CMTime(value: frameIndex, timescale: 30)
            adaptor.append(pb, withPresentationTime: presentation)
            frameIndex += 1
            try? await Task.sleep(for: .seconds(frameInterval))
        }

        writerInput.markAsFinished()
        await writer.finishWriting()

        if writer.status != .completed {
            throw writer.error ?? NSError(domain: "ScreenFaceRecorder", code: -1)
        }

        let aspect = Double(outW) / Double(outH)
        return Output(url: outputURL, aspectRatio: aspect)
    }
}
