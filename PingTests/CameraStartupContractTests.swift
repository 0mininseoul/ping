import XCTest

final class CameraStartupContractTests: XCTestCase {
    func testMirrorStartupDoesNotConfigureAudioInputBeforeRecording() throws {
        let source = try readSourceFile("Ping/Capture/CameraManager.swift")
        let configure = try sourceSlice(
            in: source,
            from: "func configure() async",
            to: "func prepareAudioForRecording() async"
        )

        XCTAssertFalse(configure.contains("requestAccess(for: .audio)"))
        XCTAssertFalse(configure.contains("AVCaptureDevice.default(for: .audio)"))
    }

    func testRecordingPreparesAudioLazilyAfterCameraIsReady() throws {
        let source = try readSourceFile("Ping/UI/Mirror/MirrorView.swift")
        let recording = try sourceSlice(
            in: source,
            from: "private func startRecording() async",
            to: "private func currentRoom()"
        )

        XCTAssertTrue(recording.contains("await camera.prepareAudioForRecording()"))
        let prepareAudio = try XCTUnwrap(recording.range(of: "await camera.prepareAudioForRecording()"))
        let recorder = try XCTUnwrap(recording.range(of: "let recorder = VideoRecorder"))
        XCTAssertLessThan(prepareAudio.lowerBound, recorder.lowerBound)
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
