import XCTest

final class KeyboardRoutingContractTests: XCTestCase {
    func testMirrorPresentationRestartsCameraAfterEscCloseReusesWindow() throws {
        let source = try readSourceFile("Ping/AppDelegate.swift")
        let showMirror = try sourceSlice(
            in: source,
            from: "private func showMirror()",
            to: "private func startCameraForMirrorPresentation()"
        )

        XCTAssertTrue(source.contains("private func startCameraForMirrorPresentation()"))
        XCTAssertTrue(showMirror.contains("startCameraForMirrorPresentation()"))
        XCTAssertTrue(source.contains("await camera.startWithAudio()"))
    }

    func testMirrorCameraStopsImmediatelyWhenMirrorCloses() throws {
        let source = try readSourceFile("Ping/AppDelegate.swift")
        let startCamera = try sourceSlice(
            in: source,
            from: "private func startCameraForMirrorPresentation()",
            to: "private func closeMirrorWindow()"
        )
        let closeMirror = try sourceSlice(
            in: source,
            from: "private func closeMirrorWindow()",
            to: "private func sendVideo"
        )

        XCTAssertTrue(source.contains("private var cameraStartTask: Task<Void, Never>?"))
        XCTAssertFalse(source.contains("private var cameraIdleStopTask"))
        XCTAssertFalse(source.contains("private func scheduleCameraIdleStop"))
        XCTAssertTrue(startCamera.contains("cameraStartTask?.cancel()"))
        XCTAssertTrue(startCamera.contains("cameraStartTask = Task"))
        XCTAssertTrue(closeMirror.contains("cameraStartTask?.cancel()"))
        XCTAssertTrue(closeMirror.contains("cameraStartTask = nil"))
        XCTAssertTrue(closeMirror.contains("camera.stop()"))
        XCTAssertFalse(closeMirror.contains("Task.sleep"))
    }

    func testAppDoesNotPrewarmCameraOnLaunch() throws {
        let source = try readSourceFile("Ping/AppDelegate.swift")
        let launch = try sourceSlice(
            in: source,
            from: "func applicationDidFinishLaunching",
            to: "func applicationWillTerminate"
        )

        XCTAssertFalse(launch.contains("prewarmCameraIfAuthorized()"))
        XCTAssertFalse(source.contains("private func prewarmCameraIfAuthorized()"))
        XCTAssertFalse(source.contains("startIfAuthorized()"))
    }

    func testMirrorKeyMonitorIgnoresNonMirrorWindows() throws {
        let source = try readSourceFile("Ping/UI/Mirror/MirrorView.swift")
        let monitor = try sourceSlice(
            in: source,
            from: "keyMonitor = NSEvent.addLocalMonitorForEvents",
            to: "private static func numericKeyIndex"
        )

        XCTAssertTrue(monitor.contains("event.window is MirrorWindow"))
        XCTAssertTrue(monitor.contains("return event"))
        XCTAssertTrue(monitor.contains("case 18, 19, 20, 21, 23, 22, 26, 28, 25"))
        XCTAssertTrue(monitor.contains("case 29, 0"))
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
