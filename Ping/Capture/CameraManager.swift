@preconcurrency import AVFoundation
import AppKit
import Combine

@MainActor
final class CameraManager: ObservableObject {
    let session = AVCaptureSession()
    private(set) var movieOutput = AVCaptureMovieFileOutput()

    @Published var isReady = false
    @Published var lastError: String?

    private var configured = false
    private var audioConfigured = false

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

        guard let camera = AVCaptureDevice.default(for: .video),
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

        configureFrameRate(for: camera)
        session.commitConfiguration()

        guard !Task.isCancelled else { return }

        configured = true
        session.startRunning()
        isReady = session.isRunning
    }

    func startIfAuthorized() async {
        guard AVCaptureDevice.authorizationStatus(for: .video) == .authorized else {
            return
        }

        await start()
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
