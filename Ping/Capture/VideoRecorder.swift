@preconcurrency import AVFoundation
import Foundation

@MainActor
final class VideoRecorder: NSObject, AVCaptureFileOutputRecordingDelegate {
    private let movieOutput: AVCaptureMovieFileOutput
    private var continuation: CheckedContinuation<URL, Error>?

    init(output: AVCaptureMovieFileOutput) {
        self.movieOutput = output
    }

    func recordTwoSeconds() async throws -> URL {
        let tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("ping-\(UUID().uuidString).mp4")

        if movieOutput.isRecording {
            movieOutput.stopRecording()
        }

        movieOutput.maxRecordedDuration = CMTime(seconds: 2.0, preferredTimescale: 600)
        movieOutput.startRecording(to: tempURL, recordingDelegate: self)

        return try await withCheckedThrowingContinuation { continuation in
            self.continuation = continuation
        }
    }

    nonisolated func fileOutput(
        _ output: AVCaptureFileOutput,
        didFinishRecordingTo outputFileURL: URL,
        from connections: [AVCaptureConnection],
        error: Error?
    ) {
        Task { @MainActor in
            if let error {
                let nsError = error as NSError
                let finishedSuccessfully = nsError.userInfo[AVErrorRecordingSuccessfullyFinishedKey] as? Bool == true
                if finishedSuccessfully {
                    continuation?.resume(returning: outputFileURL)
                } else {
                    continuation?.resume(throwing: error)
                }
            } else {
                continuation?.resume(returning: outputFileURL)
            }
            continuation = nil
        }
    }
}
