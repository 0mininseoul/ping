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

    func testMirrorHintsIncludeEscapeCloseGuidance() throws {
        let source = try readSourceFile("Ping/UI/Mirror/MirrorView.swift")

        XCTAssertTrue(source.contains("↵ 녹화 · Esc"))
        XCTAssertTrue(source.contains("⌥ Option 키를 누른 채 스크롤해 확대·축소하고"))
        XCTAssertTrue(source.contains("커서를 움직여 보낼 영역을 맞춰보세요."))
        XCTAssertTrue(source.contains("↵ Enter 녹화 시작"))
        XCTAssertTrue(source.contains("Esc 닫기"))
        XCTAssertTrue(source.contains("↵ 보내기 · ⌫ 다시 · Esc"))
    }

    func testScreenFaceGuideCompactsToOneLineAfterThreeSeconds() throws {
        let source = try readSourceFile("Ping/UI/Mirror/MirrorView.swift")
        let compactGuide = try sourceSlice(
            in: source,
            from: "if isCompact",
            to: "} else {"
        )

        XCTAssertTrue(source.contains("startViewportGuideTimer()"))
        XCTAssertTrue(source.contains("Task.sleep(for: .seconds(3))"))
        XCTAssertTrue(source.contains("isViewportGuideCompact = true"))
        XCTAssertTrue(source.contains("⌥ 스크롤·커서 이동   ↵ 녹화 시작   Esc 닫기"))
        XCTAssertFalse(compactGuide.contains("VStack"))
    }

    func testScreenFaceViewportInputIsOptionScopedAndLocksDuringRecording() throws {
        let source = try readSourceFile("Ping/UI/Mirror/MirrorView.swift")

        XCTAssertTrue(source.contains("NSEvent.addGlobalMonitorForEvents"))
        XCTAssertTrue(source.contains("NSEvent.addLocalMonitorForEvents"))
        XCTAssertTrue(source.contains("event.modifierFlags.contains(.option)"))
        XCTAssertTrue(source.contains("NSEvent.modifierFlags.contains(.option)"))
        XCTAssertTrue(source.contains("trackViewportToPointerIfNeeded()"))
        XCTAssertTrue(source.contains("case .idle, .failed:"))
        XCTAssertTrue(source.contains("case .recording, .reviewing, .uploading:"))
        XCTAssertTrue(source.contains("case 29 where captureMode == .screenFace"))
        XCTAssertTrue(source.contains("viewport.reset()"))
    }

    func testMirrorSendsCheckedRoomTargets() throws {
        let source = try readSourceFile("Ping/UI/Mirror/MirrorView.swift")
        let targets = try sourceSlice(
            in: source,
            from: "private func currentTargets() -> [Room]",
            to: "private func uploadReviewedClip"
        )

        XCTAssertTrue(source.contains("@State private var selectedRoomIds = Set<String>()"))
        XCTAssertTrue(source.contains("selectedRoomIds = Set(activeRooms.compactMap(\\.id))"))
        XCTAssertTrue(targets.contains("selectedRoomIds.contains(id)"))
    }

    func testPartnerPickerUsesCheckboxesForMultiRoomSelection() throws {
        let source = try readSourceFile("Ping/UI/Mirror/PartnerPicker.swift")

        XCTAssertTrue(source.contains("@Binding var selectedRoomIds: Set<String>"))
        XCTAssertTrue(source.contains("checkmark.square.fill"))
        XCTAssertTrue(source.contains("setRoom(room, selected: !isSelected(room))"))
        XCTAssertTrue(source.contains("return \"👥 \\(selected.count)개 룸\""))
        XCTAssertFalse(source.contains("isExpanded = false"))
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
