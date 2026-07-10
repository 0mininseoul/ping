import XCTest

final class ScreenCaptureFilteringContractTests: XCTestCase {
    func testCaptureManagerFailsClosedWhenPingCannotBeExcluded() throws {
        let source = try readSourceFile("ScreenCaptureManager.swift")

        XCTAssertTrue(source.contains("SelfCaptureFilterPolicy.matchingApplications"))
        XCTAssertTrue(source.contains("Bundle.main.bundleIdentifier"))
        XCTAssertTrue(source.contains("maximumSelfApplicationLookupAttempts"))
        XCTAssertTrue(source.contains("guard !excludedApplications.isEmpty else"))
        XCTAssertTrue(source.contains("throw CaptureSetupError.currentApplicationUnavailable"))
        XCTAssertFalse(source.contains("myApp.map { [$0] } ?? []"))
    }

    func testMirrorIsPresentedBeforePreviewCaptureBegins() throws {
        let source = try readSourceFile("AppDelegate.swift")
        let showMirror = try sourceSlice(
            in: source,
            from: "private func showMirror()",
            to: "private func startCameraForMirrorPresentation()"
        )
        let present = try XCTUnwrap(showMirror.range(of: "ForegroundPresenter.present(mirrorWindow)"))
        let start = try XCTUnwrap(showMirror.range(of: "await self.screenCapture.startPreview"))

        XCTAssertLessThan(present.lowerBound, start.lowerBound)
        XCTAssertTrue(showMirror.contains("await Task.yield()"))
        XCTAssertTrue(showMirror.contains("window === self.mirrorWindow"))
    }

    private func readSourceFile(_ fileName: String) throws -> String {
        let fileURL = try XCTUnwrap(Bundle(for: Self.self).resourceURL?.appendingPathComponent(fileName))
        return try String(contentsOf: fileURL, encoding: .utf8)
    }

    private func sourceSlice(in source: String, from startMarker: String, to endMarker: String) throws -> String {
        let start = try XCTUnwrap(source.range(of: startMarker)?.lowerBound)
        let end = try XCTUnwrap(source.range(of: endMarker, range: start..<source.endIndex)?.lowerBound)
        return String(source[start..<end])
    }
}
