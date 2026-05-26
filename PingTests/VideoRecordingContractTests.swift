import XCTest

final class VideoRecordingContractTests: XCTestCase {
    func testRecorderCropsCameraFrameBeforeSendingOrSaving() throws {
        let recorderSource = try readSourceFile("Ping/Capture/VideoRecorder.swift")
        let cropperSource = try readSourceFile("Ping/Capture/VideoCropper.swift")

        XCTAssertTrue(recorderSource.contains("VideoCropper.cropToSquare"))
        XCTAssertTrue(cropperSource.contains("AVMutableVideoComposition"))
        XCTAssertTrue(cropperSource.contains("min(displaySize.width, displaySize.height)"))
        XCTAssertTrue(cropperSource.contains("renderSize = CGSize(width: side, height: side)"))
    }

    func testScreenFaceRecorderWritesMicrophoneAudioTrack() throws {
        let recorderSource = try readSourceFile("Ping/Capture/ScreenFaceRecorder.swift")

        XCTAssertTrue(recorderSource.contains("AVCaptureAudioDataOutput"))
        XCTAssertTrue(recorderSource.contains("AVAssetWriterInput(mediaType: .audio"))
        XCTAssertTrue(recorderSource.contains("appendAudioSampleBuffer"))
        XCTAssertTrue(recorderSource.contains("audioOutput.setSampleBufferDelegate"))
        XCTAssertTrue(recorderSource.contains("cameraSession.addOutput(audioOutput)"))
        XCTAssertTrue(recorderSource.contains("cameraSession.removeOutput(audioOutput)"))
    }

    func testReviewLoopPlaybackKeepsAudioAudible() throws {
        let source = try readSourceFile("Ping/UI/Mirror/MirrorView.swift")
        let reviewLoop = try sourceSlice(
            in: source,
            from: "struct ReviewLoopPlayerView",
            to: "struct HintCapsuleView"
        )

        XCTAssertTrue(reviewLoop.contains("player.isMuted = false"))
        XCTAssertFalse(reviewLoop.contains("player.isMuted = true"))
    }

    private func readSourceFile(_ relativePath: String) throws -> String {
        let fileName = URL(fileURLWithPath: relativePath).lastPathComponent
        let fileURL = try XCTUnwrap(Bundle(for: Self.self).resourceURL?.appendingPathComponent(fileName))

        return try String(contentsOf: fileURL, encoding: .utf8)
    }

    private func sourceSlice(in source: String, from startMarker: String, to endMarker: String) throws -> String {
        let start = try XCTUnwrap(source.range(of: startMarker)?.lowerBound)
        let end = try XCTUnwrap(source.range(of: endMarker, range: start..<source.endIndex)?.lowerBound)

        return String(source[start..<end])
    }
}
