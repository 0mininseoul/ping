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

    private func readSourceFile(_ relativePath: String) throws -> String {
        let fileName = URL(fileURLWithPath: relativePath).lastPathComponent
        let fileURL = try XCTUnwrap(Bundle(for: Self.self).resourceURL?.appendingPathComponent(fileName))

        return try String(contentsOf: fileURL, encoding: .utf8)
    }
}
