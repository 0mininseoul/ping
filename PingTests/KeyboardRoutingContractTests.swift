import XCTest

final class KeyboardRoutingContractTests: XCTestCase {
    func testMirrorPresentationRestartsCameraAfterEscCloseReusesWindow() throws {
        let source = try readSourceFile("Ping/AppDelegate.swift")
        let toggleMirror = try sourceSlice(
            in: source,
            from: "private func toggleMirror()",
            to: "private func closeMirrorWindow()"
        )

        XCTAssertTrue(source.contains("private func startCameraForMirrorPresentation()"))
        XCTAssertTrue(toggleMirror.contains("startCameraForMirrorPresentation()"))
        XCTAssertTrue(source.contains("await camera.start()"))
    }

    func testMirrorCameraStartTaskIsCanceledWhenMirrorClosesButCameraStaysWarmBriefly() throws {
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
        let idleStop = try sourceSlice(
            in: source,
            from: "private func scheduleCameraIdleStop()",
            to: "private func sendVideo"
        )

        XCTAssertTrue(source.contains("private var cameraStartTask: Task<Void, Never>?"))
        XCTAssertTrue(source.contains("private var cameraIdleStopTask: Task<Void, Never>?"))
        XCTAssertTrue(startCamera.contains("cameraStartTask?.cancel()"))
        XCTAssertTrue(startCamera.contains("cameraIdleStopTask?.cancel()"))
        XCTAssertTrue(startCamera.contains("cameraStartTask = Task"))
        XCTAssertTrue(closeMirror.contains("cameraStartTask?.cancel()"))
        XCTAssertTrue(closeMirror.contains("cameraStartTask = nil"))
        XCTAssertTrue(closeMirror.contains("scheduleCameraIdleStop()"))
        XCTAssertFalse(closeMirror.contains("camera.stop()"))
        XCTAssertTrue(idleStop.contains("cameraIdleStopTask = Task"))
        XCTAssertTrue(idleStop.contains("try? await Task.sleep(for: .minutes(5))"))
        XCTAssertTrue(idleStop.contains("camera.stop()"))
    }

    func testAppPrewarmsCameraWhenPermissionAlreadyGranted() throws {
        let source = try readSourceFile("Ping/AppDelegate.swift")
        let launch = try sourceSlice(
            in: source,
            from: "func applicationDidFinishLaunching",
            to: "func applicationWillTerminate"
        )
        let prewarm = try sourceSlice(
            in: source,
            from: "private func prewarmCameraIfAuthorized()",
            to: "private func bootstrapBackend() async"
        )

        XCTAssertTrue(launch.contains("prewarmCameraIfAuthorized()"))
        XCTAssertTrue(prewarm.contains("cameraIdleStopTask?.cancel()"))
        XCTAssertTrue(prewarm.contains("await camera.startIfAuthorized()"))
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
