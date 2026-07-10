import AppKit
@preconcurrency import ScreenCaptureKit
import Combine
import CoreImage
import CoreMedia
import OSLog

@MainActor
final class ScreenCaptureManager: NSObject, ObservableObject {
    private enum CaptureSetupError: LocalizedError {
        case currentApplicationUnavailable

        var errorDescription: String? {
            switch self {
            case .currentApplicationUnavailable:
                return "Ping 프리뷰를 화면 캡처에서 제외하지 못했습니다. 창을 닫았다가 다시 열어주세요."
            }
        }
    }

    private static let maximumSelfApplicationLookupAttempts = 3
    private static let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "com.youngminpark.ping.Ping",
        category: "ScreenCapture"
    )

    @Published private(set) var latestFrame: CIImage?
    @Published private(set) var lastError: String?

    private var stream: SCStream?
    private var output: FrameOutput?
    private var streamGeneration = 0

    func startPreview(on screen: NSScreen) async {
        await start(on: screen, frameRateHz: 24)
    }

    func startRecording(on screen: NSScreen) async {
        await start(on: screen, frameRateHz: 30)
    }

    func stop() async {
        streamGeneration &+= 1
        let streamToStop = stream
        self.stream = nil
        output = nil
        latestFrame = nil
        guard let streamToStop else { return }
        try? await streamToStop.stopCapture()
    }

    private func start(on screen: NSScreen, frameRateHz: Int) async {
        streamGeneration &+= 1
        let generation = streamGeneration

        // Tear down any existing stream (e.g. the live preview) first so we never
        // run two capture streams on the same display at once.
        if let existing = stream {
            stream = nil
            output = nil
            try? await existing.stopCapture()
        }
        guard generation == streamGeneration else { return }

        latestFrame = nil
        lastError = nil

        do {
            let (content, excludedApplications) = try await shareableContentExcludingCurrentApplication()
            guard generation == streamGeneration else { return }
            guard let display = matchingDisplay(in: content.displays, for: screen) else {
                lastError = "디스플레이를 찾지 못함"
                return
            }

            let filter = SCContentFilter(
                display: display,
                excludingApplications: excludedApplications,
                exceptingWindows: []
            )
            let config = SCStreamConfiguration()
            config.width = Int(display.width)
            config.height = Int(display.height)
            config.minimumFrameInterval = CMTime(value: 1, timescale: Int32(frameRateHz))
            config.queueDepth = 5
            config.showsCursor = true

            let frameOutput = FrameOutput()
            let newStream = SCStream(filter: filter, configuration: config, delegate: nil)
            try newStream.addStreamOutput(
                frameOutput,
                type: .screen,
                sampleHandlerQueue: .global(qos: .userInteractive)
            )
            frameOutput.onFrame = { [weak self] image in
                Task { @MainActor in
                    guard let self, self.streamGeneration == generation else { return }
                    self.latestFrame = image
                }
            }
            try await newStream.startCapture()
            guard generation == streamGeneration else {
                try? await newStream.stopCapture()
                return
            }
            stream = newStream
            output = frameOutput
            self.lastError = nil
        } catch {
            guard generation == streamGeneration else { return }
            latestFrame = nil
            self.lastError = error.localizedDescription
            Self.logger.error("Screen capture setup failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    private func shareableContentExcludingCurrentApplication() async throws
        -> (SCShareableContent, [SCRunningApplication]) {
        let bundleIdentifier = Bundle.main.bundleIdentifier
        let processID = ProcessInfo.processInfo.processIdentifier

        for attempt in 1...Self.maximumSelfApplicationLookupAttempts {
            let content = try await SCShareableContent.excludingDesktopWindows(
                false,
                onScreenWindowsOnly: true
            )
            let excludedApplications = SelfCaptureFilterPolicy.matchingApplications(
                in: content.applications,
                bundleIdentifier: bundleIdentifier,
                processID: processID,
                bundleIdentifierOf: { $0.bundleIdentifier },
                processIDOf: { $0.processID }
            )

            guard !excludedApplications.isEmpty else {
                Self.logger.warning(
                    "Ping missing from shareable applications (attempt \(attempt, privacy: .public))"
                )
                if attempt < Self.maximumSelfApplicationLookupAttempts {
                    try await Task.sleep(for: .milliseconds(80))
                    continue
                }
                throw CaptureSetupError.currentApplicationUnavailable
            }

            return (content, excludedApplications)
        }

        throw CaptureSetupError.currentApplicationUnavailable
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
