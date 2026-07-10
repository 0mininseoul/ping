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
        viewport: ScreenCaptureViewport = ScreenCaptureViewport(),
        duration: TimeInterval = 3.0
    ) async throws -> Output {
        let outputURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("ping-sf-\(UUID().uuidString).mp4")
        try? FileManager.default.removeItem(at: outputURL)

        let longSide: CGFloat = 540
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
                AVVideoAverageBitRateKey: 1_200_000,
                AVVideoExpectedSourceFrameRateKey: 30,
                AVVideoMaxKeyFrameIntervalKey: 30
            ]
        ]

        let writerInput = AVAssetWriterInput(mediaType: .video, outputSettings: videoSettings)
        writerInput.expectsMediaDataInRealTime = true
        let audioInput = AVAssetWriterInput(mediaType: .audio, outputSettings: [
            AVFormatIDKey: kAudioFormatMPEG4AAC,
            AVNumberOfChannelsKey: 1,
            AVSampleRateKey: 44_100,
            AVEncoderBitRateKey: 64_000
        ])
        audioInput.expectsMediaDataInRealTime = true

        let adaptor = AVAssetWriterInputPixelBufferAdaptor(
            assetWriterInput: writerInput,
            sourcePixelBufferAttributes: [
                kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
                kCVPixelBufferWidthKey as String: outW,
                kCVPixelBufferHeightKey as String: outH
            ]
        )

        writer.add(writerInput)
        if writer.canAdd(audioInput) {
            writer.add(audioInput)
        } else {
            throw NSError(
                domain: "ScreenFaceRecorder",
                code: -2,
                userInfo: [NSLocalizedDescriptionKey: "마이크 오디오 트랙을 준비할 수 없습니다."]
            )
        }

        let audioOutput = AVCaptureAudioDataOutput()
        let audioQueue = DispatchQueue(label: "ping.screen-face.audio")
        let audioSampleWriter = AudioSampleWriter(input: audioInput)
        let hasAudioInput = cameraSession.inputs.contains { input in
            input.ports.contains { $0.mediaType == .audio }
        }
        guard hasAudioInput else {
            throw NSError(
                domain: "ScreenFaceRecorder",
                code: -3,
                userInfo: [NSLocalizedDescriptionKey: "마이크 입력이 준비되지 않았습니다."]
            )
        }
        guard cameraSession.canAddOutput(audioOutput) else {
            throw NSError(
                domain: "ScreenFaceRecorder",
                code: -4,
                userInfo: [NSLocalizedDescriptionKey: "마이크 입력을 녹음 세션에 연결할 수 없습니다."]
            )
        }

        var isAudioOutputAdded = false
        func stopAudioCapture() {
            guard isAudioOutputAdded else { return }
            audioSampleWriter.finish()
            audioOutput.setSampleBufferDelegate(nil, queue: nil)
            cameraSession.beginConfiguration()
            cameraSession.removeOutput(audioOutput)
            cameraSession.commitConfiguration()
            isAudioOutputAdded = false
        }

        cameraSession.beginConfiguration()
        cameraSession.addOutput(audioOutput)
        cameraSession.commitConfiguration()
        isAudioOutputAdded = true

        writer.startWriting()
        writer.startSession(atSourceTime: .zero)
        audioOutput.setSampleBufferDelegate(audioSampleWriter, queue: audioQueue)
        defer { stopAudioCapture() }

        let ciContext = CIContext()
        let start = Date()
        let frameInterval: TimeInterval = 1.0 / 30.0
        var lastPresentation: CMTime = .zero
        var hasAppended = false

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

            let croppedScreen = viewport.cropped(screenImage)
            let sx = outputSize.width / croppedScreen.extent.width
            let sy = outputSize.height / croppedScreen.extent.height
            let scaledScreen = croppedScreen.transformed(by: CGAffineTransform(scaleX: sx, y: sy))
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

            // Stamp by real elapsed time so the clip is a true `duration`
            // seconds at natural speed. A frame counter under-rates whenever the
            // composite loop can't sustain 30fps, which shortened and sped up
            // the clip.
            var presentation = CMTime(seconds: Date().timeIntervalSince(start), preferredTimescale: 600)
            if hasAppended, presentation <= lastPresentation {
                presentation = lastPresentation + CMTime(value: 1, timescale: 600)
            }
            adaptor.append(pb, withPresentationTime: presentation)
            lastPresentation = presentation
            hasAppended = true
            try? await Task.sleep(for: .seconds(frameInterval))
        }

        stopAudioCapture()
        writerInput.markAsFinished()
        audioInput.markAsFinished()
        await writer.finishWriting()

        if writer.status != .completed {
            throw writer.error ?? NSError(domain: "ScreenFaceRecorder", code: -1)
        }

        let aspect = Double(outW) / Double(outH)
        return Output(url: outputURL, aspectRatio: aspect)
    }

    private final class AudioSampleWriter: NSObject, AVCaptureAudioDataOutputSampleBufferDelegate {
        private let input: AVAssetWriterInput
        private let lock = NSLock()
        private var firstPresentationTime: CMTime?
        private var isFinished = false

        init(input: AVAssetWriterInput) {
            self.input = input
        }

        func finish() {
            lock.lock()
            isFinished = true
            lock.unlock()
        }

        func captureOutput(
            _ output: AVCaptureOutput,
            didOutput sampleBuffer: CMSampleBuffer,
            from connection: AVCaptureConnection
        ) {
            appendAudioSampleBuffer(sampleBuffer)
        }

        private func appendAudioSampleBuffer(_ sampleBuffer: CMSampleBuffer) {
            lock.lock()
            defer { lock.unlock() }

            guard !isFinished,
                  input.isReadyForMoreMediaData else {
                return
            }

            let presentationTime = CMSampleBufferGetPresentationTimeStamp(sampleBuffer)
            if firstPresentationTime == nil {
                firstPresentationTime = presentationTime
            }
            guard let baseTime = firstPresentationTime else { return }

            var timingCount = 0
            CMSampleBufferGetSampleTimingInfoArray(
                sampleBuffer,
                entryCount: 0,
                arrayToFill: nil,
                entriesNeededOut: &timingCount
            )
            guard timingCount > 0 else { return }

            var timing = Array(
                repeating: CMSampleTimingInfo(
                    duration: .invalid,
                    presentationTimeStamp: .invalid,
                    decodeTimeStamp: .invalid
                ),
                count: timingCount
            )
            CMSampleBufferGetSampleTimingInfoArray(
                sampleBuffer,
                entryCount: timingCount,
                arrayToFill: &timing,
                entriesNeededOut: &timingCount
            )

            for index in timing.indices {
                if timing[index].presentationTimeStamp.isValid {
                    timing[index].presentationTimeStamp = CMTimeSubtract(
                        timing[index].presentationTimeStamp,
                        baseTime
                    )
                }
                if timing[index].decodeTimeStamp.isValid {
                    timing[index].decodeTimeStamp = CMTimeSubtract(
                        timing[index].decodeTimeStamp,
                        baseTime
                    )
                }
            }

            var retimedSampleBuffer: CMSampleBuffer?
            let status = timing.withUnsafeBufferPointer { buffer in
                CMSampleBufferCreateCopyWithNewTiming(
                    allocator: kCFAllocatorDefault,
                    sampleBuffer: sampleBuffer,
                    sampleTimingEntryCount: timing.count,
                    sampleTimingArray: buffer.baseAddress,
                    sampleBufferOut: &retimedSampleBuffer
                )
            }

            guard status == noErr,
                  let retimedSampleBuffer else {
                return
            }
            input.append(retimedSampleBuffer)
        }
    }
}
