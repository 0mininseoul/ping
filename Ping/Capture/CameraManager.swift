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

    func start() async {
        if configured {
            if !session.isRunning {
                session.startRunning()
            }
            return
        }

        await configure()
    }

    func configure() async {
        guard !configured else {
            if !session.isRunning {
                session.startRunning()
            }
            return
        }

        let cameraGranted = await AVCaptureDevice.requestAccess(for: .video)
        guard cameraGranted else {
            lastError = "카메라 권한이 필요합니다."
            return
        }

        _ = await AVCaptureDevice.requestAccess(for: .audio)

        session.beginConfiguration()
        session.sessionPreset = .hd1920x1080

        guard let camera = AVCaptureDevice.default(for: .video),
              let cameraInput = try? AVCaptureDeviceInput(device: camera),
              session.canAddInput(cameraInput) else {
            lastError = "카메라 디바이스를 찾을 수 없습니다."
            session.commitConfiguration()
            return
        }

        if let audio = AVCaptureDevice.default(for: .audio),
           let audioInput = try? AVCaptureDeviceInput(device: audio),
           session.canAddInput(audioInput) {
            session.addInput(audioInput)
        }

        session.addInput(cameraInput)

        if session.canAddOutput(movieOutput) {
            session.addOutput(movieOutput)
        }

        configureFrameRate(for: camera)
        session.commitConfiguration()

        configured = true
        isReady = true
        session.startRunning()
    }

    func stop() {
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
