import AppKit
@preconcurrency import ScreenCaptureKit
import Combine
import CoreImage
import CoreMedia

@MainActor
final class ScreenCaptureManager: NSObject, ObservableObject {
    @Published private(set) var latestFrame: CIImage?
    @Published private(set) var lastError: String?

    private var stream: SCStream?
    private let output = FrameOutput()

    func startPreview(on screen: NSScreen) async {
        await start(on: screen, frameRateHz: 24)
    }

    func startRecording(on screen: NSScreen) async {
        await start(on: screen, frameRateHz: 30)
    }

    func stop() async {
        guard let stream else { return }
        try? await stream.stopCapture()
        self.stream = nil
    }

    private func start(on screen: NSScreen, frameRateHz: Int) async {
        do {
            let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
            guard let display = matchingDisplay(in: content.displays, for: screen) else {
                lastError = "디스플레이를 찾지 못함"
                return
            }

            let pid = ProcessInfo.processInfo.processIdentifier
            let myApp = content.applications.first { $0.processID == pid }
            let exclusions = myApp.map { [$0] } ?? []

            let filter = SCContentFilter(display: display, excludingApplications: exclusions, exceptingWindows: [])
            let config = SCStreamConfiguration()
            config.width = Int(display.width)
            config.height = Int(display.height)
            config.minimumFrameInterval = CMTime(value: 1, timescale: Int32(frameRateHz))
            config.queueDepth = 5
            config.showsCursor = true

            let stream = SCStream(filter: filter, configuration: config, delegate: nil)
            try stream.addStreamOutput(output, type: .screen, sampleHandlerQueue: .global(qos: .userInteractive))
            output.onFrame = { [weak self] image in
                Task { @MainActor in self?.latestFrame = image }
            }
            try await stream.startCapture()
            self.stream = stream
            self.lastError = nil
        } catch {
            self.lastError = error.localizedDescription
        }
    }

    private func matchingDisplay(in displays: [SCDisplay], for screen: NSScreen) -> SCDisplay? {
        if let exact = displays.first(where: { CGRect(origin: .zero, size: CGSize(width: $0.width, height: $0.height)) == CGRect(origin: .zero, size: screen.frame.size) }) {
            return exact
        }
        return displays.first
    }

    final class FrameOutput: NSObject, SCStreamOutput {
        nonisolated(unsafe) var onFrame: ((CIImage) -> Void)?

        func stream(_ stream: SCStream, didOutputSampleBuffer sampleBuffer: CMSampleBuffer, of type: SCStreamOutputType) {
            guard type == .screen, sampleBuffer.isValid,
                  let pixelBuffer = sampleBuffer.imageBuffer else { return }
            let image = CIImage(cvPixelBuffer: pixelBuffer)
            onFrame?(image)
        }
    }
}
