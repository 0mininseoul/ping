@preconcurrency import AVFoundation
import AppKit
import Combine
import CoreImage

@MainActor
final class CameraManager: NSObject, ObservableObject {
    nonisolated(unsafe) static var latestVideoFrame: CIImage?

    let session = AVCaptureSession()
    private(set) var movieOutput = AVCaptureMovieFileOutput()

    private let videoDataOutput = AVCaptureVideoDataOutput()
    private let videoFrameQueue = DispatchQueue(label: "ping.camera.frame")

    @Published var isReady = false
    @Published var lastError: String?

    private var configured = false
    private var audioConfigured = false

    func startWithAudio() async {
        await start()
        guard isReady else { return }
        await prepareAudioForRecording()
    }

    /// Robustly resolve an available camera. `AVCaptureDevice.default(for: .video)`
    /// can return nil on newer macOS (multiple cameras / Continuity Camera) even
    /// when a camera is present, surfacing as "디바이스를 찾을 수 없습니다". A
    /// DiscoverySession enumerates concrete device types and prefers the built-in.
    static func preferredCamera() -> AVCaptureDevice? {
        var deviceTypes: [AVCaptureDevice.DeviceType] = [.builtInWideAngleCamera, .deskViewCamera]
        if #available(macOS 14.0, *) {
            deviceTypes.append(contentsOf: [.external, .continuityCamera])
        }
        let discovery = AVCaptureDevice.DiscoverySession(
            deviceTypes: deviceTypes,
            mediaType: .video,
            position: .unspecified
        )
        return discovery.devices.first { $0.deviceType == .builtInWideAngleCamera }
            ?? discovery.devices.first
            ?? AVCaptureDevice.default(for: .video)
    }

    func start() async {
        guard !Task.isCancelled else { return }

        if configured {
            if !session.isRunning {
                isReady = false
                session.startRunning()
            }
            isReady = session.isRunning
            return
        }

        await configure()
    }

    func configure() async {
        guard !Task.isCancelled else { return }

        guard !configured else {
            if !session.isRunning {
                isReady = false
                session.startRunning()
            }
            isReady = session.isRunning
            return
        }

        let cameraGranted = await AVCaptureDevice.requestAccess(for: .video)
        guard !Task.isCancelled else { return }
        guard cameraGranted else {
            lastError = "카메라 권한이 필요합니다."
            return
        }

        session.beginConfiguration()
        session.sessionPreset = .hd1920x1080

        guard let camera = Self.preferredCamera(),
              let cameraInput = try? AVCaptureDeviceInput(device: camera),
              session.canAddInput(cameraInput) else {
            lastError = "카메라 디바이스를 찾을 수 없습니다."
            session.commitConfiguration()
            return
        }

        session.addInput(cameraInput)

        if session.canAddOutput(movieOutput) {
            session.addOutput(movieOutput)
        }

        videoDataOutput.alwaysDiscardsLateVideoFrames = true
        videoDataOutput.videoSettings = [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA
        ]
        videoDataOutput.setSampleBufferDelegate(self, queue: videoFrameQueue)
        if session.canAddOutput(videoDataOutput) {
            session.addOutput(videoDataOutput)
        }

        configureFrameRate(for: camera)
        session.commitConfiguration()

        guard !Task.isCancelled else { return }

        configured = true
        session.startRunning()
        isReady = session.isRunning
    }

    func prepareAudioForRecording() async {
        guard !audioConfigured, !Task.isCancelled else { return }

        if session.inputs.contains(where: { input in
            input.ports.contains { $0.mediaType == .audio }
        }) {
            audioConfigured = true
            return
        }

        let audioGranted = await AVCaptureDevice.requestAccess(for: .audio)
        guard audioGranted, !Task.isCancelled else { return }

        guard let audio = AVCaptureDevice.default(for: .audio),
              let audioInput = try? AVCaptureDeviceInput(device: audio),
              session.canAddInput(audioInput) else {
            return
        }

        session.beginConfiguration()
        session.addInput(audioInput)
        session.commitConfiguration()
        audioConfigured = true
    }

    func stop() {
        isReady = false
        guard session.isRunning else { return }
        session.stopRunning()
    }

    private func configureFrameRate(for device: AVCaptureDevice) {
        do {
            try device.lockForConfiguration()
            device.activeVideoMinFrameDuration = CMTime(value: 1, timescale: 30)
            device.activeVideoMaxFrameDuration = CMTime(value: 1, timescale: 30)
            device.unlockForConfiguration()
        } catch {
            lastError = "카메라 프레임레이트 설정에 실패했습니다: \(error.localizedDescription)"
        }
    }
}

extension CameraManager: AVCaptureVideoDataOutputSampleBufferDelegate {
    nonisolated func captureOutput(
        _ output: AVCaptureOutput,
        didOutput sampleBuffer: CMSampleBuffer,
        from connection: AVCaptureConnection
    ) {
        guard let pb = sampleBuffer.imageBuffer else { return }
        // Copy into an independently-owned buffer so the capture output's own
        // pool buffer is released as soon as this callback returns. Retaining the
        // output's buffers (via a long-lived CIImage) can exhaust its small pool
        // and stall delivery mid-capture — which froze the face overlay ~2s into
        // screen+face clips while the screen kept updating.
        guard let copy = CameraManager.copyPixelBuffer(pb) else { return }
        CameraManager.latestVideoFrame = CIImage(cvPixelBuffer: copy)
    }

    /// Deep-copies a pixel buffer into a fresh, app-owned buffer.
    nonisolated static func copyPixelBuffer(_ source: CVPixelBuffer) -> CVPixelBuffer? {
        let width = CVPixelBufferGetWidth(source)
        let height = CVPixelBufferGetHeight(source)
        let format = CVPixelBufferGetPixelFormatType(source)

        var destination: CVPixelBuffer?
        let attributes: [String: Any] = [
            kCVPixelBufferIOSurfacePropertiesKey as String: [:],
            kCVPixelBufferCGImageCompatibilityKey as String: true,
            kCVPixelBufferCGBitmapContextCompatibilityKey as String: true
        ]
        guard CVPixelBufferCreate(
            kCFAllocatorDefault, width, height, format, attributes as CFDictionary, &destination
        ) == kCVReturnSuccess, let destination else { return nil }

        CVPixelBufferLockBaseAddress(source, .readOnly)
        CVPixelBufferLockBaseAddress(destination, [])
        defer {
            CVPixelBufferUnlockBaseAddress(destination, [])
            CVPixelBufferUnlockBaseAddress(source, .readOnly)
        }

        if CVPixelBufferIsPlanar(source) {
            for plane in 0..<CVPixelBufferGetPlaneCount(source) {
                guard let src = CVPixelBufferGetBaseAddressOfPlane(source, plane),
                      let dst = CVPixelBufferGetBaseAddressOfPlane(destination, plane) else { return nil }
                let srcStride = CVPixelBufferGetBytesPerRowOfPlane(source, plane)
                let dstStride = CVPixelBufferGetBytesPerRowOfPlane(destination, plane)
                let planeHeight = CVPixelBufferGetHeightOfPlane(source, plane)
                let rowBytes = min(srcStride, dstStride)
                for row in 0..<planeHeight {
                    memcpy(dst + row * dstStride, src + row * srcStride, rowBytes)
                }
            }
        } else {
            guard let src = CVPixelBufferGetBaseAddress(source),
                  let dst = CVPixelBufferGetBaseAddress(destination) else { return nil }
            let srcStride = CVPixelBufferGetBytesPerRow(source)
            let dstStride = CVPixelBufferGetBytesPerRow(destination)
            let rowBytes = min(srcStride, dstStride)
            for row in 0..<height {
                memcpy(dst + row * dstStride, src + row * srcStride, rowBytes)
            }
        }
        return destination
    }
}
