import XCTest
@testable import Ping

final class ScreenFaceLayoutTests: XCTestCase {
    func testFacePIPScalesFromShortestSideAcrossPreviewAndRecordingSizes() {
        let previewSize = CGSize(width: 480, height: 270)
        let recordingSize = CGSize(width: 720, height: 405)

        XCTAssertEqual(ScreenFaceLayout.faceDiameter(in: previewSize), 86.4, accuracy: 0.01)
        XCTAssertEqual(ScreenFaceLayout.padding(in: previewSize), 12.15, accuracy: 0.01)
        XCTAssertEqual(ScreenFaceLayout.faceDiameter(in: recordingSize), 129.6, accuracy: 0.01)
        XCTAssertEqual(ScreenFaceLayout.padding(in: recordingSize), 18.225, accuracy: 0.01)

        let previewRatio = ScreenFaceLayout.faceDiameter(in: previewSize) / min(previewSize.width, previewSize.height)
        let recordingRatio = ScreenFaceLayout.faceDiameter(in: recordingSize) / min(recordingSize.width, recordingSize.height)
        XCTAssertEqual(previewRatio, recordingRatio, accuracy: 0.0001)
    }

    func testPreviewRecorderAndInlineHistoryUseSharedScreenFaceLayout() throws {
        let mirrorSource = try readSourceFile("MirrorView.swift")
        let recorderSource = try readSourceFile("ScreenFaceRecorder.swift")
        let inlinePlayerSource = try readSourceFile("InlinePlayerView.swift")
        let previewSource = try sourceSlice(
            mirrorSource,
            from: "struct ScreenFacePreview",
            to: "struct ScreenLiveImageView"
        )

        XCTAssertTrue(previewSource.contains("GeometryReader"))
        XCTAssertTrue(previewSource.contains("ScreenFaceLayout.faceDiameter"))
        XCTAssertTrue(previewSource.contains("ScreenFaceLayout.padding"))
        XCTAssertFalse(previewSource.contains(".frame(width: 72, height: 72)"))
        XCTAssertTrue(mirrorSource.contains("let cropped = viewport.cropped(frame)"))

        XCTAssertTrue(recorderSource.contains("ScreenFaceLayout.faceDiameterRatio"))
        XCTAssertTrue(recorderSource.contains("ScreenFaceLayout.paddingRatio"))
        XCTAssertTrue(recorderSource.contains("let croppedScreen = viewport.cropped(screenImage)"))
        XCTAssertFalse(recorderSource.contains("72.0 / longSide"))
        XCTAssertFalse(recorderSource.contains("12.0 / longSide"))

        XCTAssertTrue(inlinePlayerSource.contains("let width: CGFloat = 420"))
    }

    private func readSourceFile(_ fileName: String) throws -> String {
        let fileURL = try XCTUnwrap(Bundle(for: Self.self).resourceURL?.appendingPathComponent(fileName))
        return try String(contentsOf: fileURL, encoding: .utf8)
    }

    private func sourceSlice(_ source: String, from start: String, to end: String) throws -> String {
        guard let startRange = source.range(of: start),
              let endRange = source.range(of: end, range: startRange.upperBound..<source.endIndex) else {
            XCTFail("Could not find source slice from \(start) to \(end)")
            return ""
        }
        return String(source[startRange.lowerBound..<endRange.lowerBound])
    }
}
