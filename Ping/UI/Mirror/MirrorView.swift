import SwiftUI
@preconcurrency import AVFoundation
import CoreImage
import Combine

struct MirrorView: View {
    @ObservedObject var camera: CameraManager
    @ObservedObject var screenCapture: ScreenCaptureManager
    let captureMode: CaptureMode
    let captureScreenFrame: CGRect
    let previewSize: CGSize
    @ObservedObject var viewModel: MirrorViewModel
    @ObservedObject var appState: AppState

    var windowOrigin: () -> NSPoint
    var onClose: () -> Void = {}
    var onSend: (URL, MirrorPosition, [Room], CaptureMode, Double) async throws -> Void

    @State private var keyMonitor: Any?
    @State private var localViewportMonitor: Any?
    @State private var globalViewportMonitor: Any?
    @State private var viewportTrackingTask: Task<Void, Never>?
    @State private var lastRecordedAspect: Double = 1.0
    @State private var selectedRoomIds = Set<String>()
    @State private var pickerExpanded = false
    @State private var viewport = ScreenCaptureViewport()

    private var mirrorShape: AnyShape {
        switch captureMode {
        case .faceOnly:
            return AnyShape(Circle())
        case .screenFace:
            return AnyShape(RoundedRectangle(cornerRadius: 16))
        }
    }

    var body: some View {
        ZStack {
            mirrorShadowSurface
            mirrorContent
        }
        .frame(width: previewSize.width, height: previewSize.height)
        .contentShape(mirrorShape)
        .onAppear {
            reconcileSelectedRooms()
            installKeyMonitor()
            installViewportMonitors()
        }
        .onChange(of: appState.rooms.map(\.id)) { _ in
            reconcileSelectedRooms()
        }
        .onDisappear {
            if let keyMonitor {
                NSEvent.removeMonitor(keyMonitor)
            }
            keyMonitor = nil
            removeViewportMonitors()
        }
    }

    private var mirrorShadowSurface: some View {
        mirrorShape
            .fill(PingDesign.Surface.circleFill)
            .pingShadow(PingDesign.Shadow.mirror)
    }

    private var mirrorContent: some View {
        ZStack {
            previewLayer
                .clipShape(mirrorShape)

            if showsRainbowBorder && captureMode == .faceOnly {
                RainbowBorder(lineWidth: 2)
            } else {
                mirrorShape.stroke(borderColor, lineWidth: borderWidth)
            }

            VStack {
                topOverlay
                Spacer()
                bottomOverlay
            }

            if showsViewportBadge {
                VStack {
                    HStack {
                        ViewportZoomBadge(zoom: viewport.zoom)
                        Spacer()
                    }
                    Spacer()
                }
                .padding(10)
                .allowsHitTesting(false)
            }
        }
        .frame(width: previewSize.width, height: previewSize.height)
        .clipShape(mirrorShape)
    }

    @ViewBuilder private var previewLayer: some View {
        if case .reviewing(let url) = viewModel.state {
            ReviewLoopPlayerView(url: url)
        } else {
            switch captureMode {
            case .faceOnly:
                CameraPreviewView(session: camera.session)
            case .screenFace:
                ScreenFacePreview(screenCapture: screenCapture, camera: camera, viewport: viewport)
            }
        }
    }

    @ViewBuilder private var topOverlay: some View {
        switch viewModel.state {
        case .idle:
            if camera.isReady {
                if captureMode == .screenFace {
                    HintCapsuleView(
                        text: "⌥스크롤 확대 · ⌥이동 · ↵ 녹화 · Esc",
                        maxWidth: 220
                    )
                    .padding(.top, 10)
                } else {
                    HintCapsuleView(text: "↵ 녹화 · Esc")
                        .padding(.top, 10)
                }
            } else {
                Text(camera.lastError ?? "카메라 준비 중")
                    .font(PingFont.caption)
                    .foregroundStyle(.white)
                    .lineLimit(2)
                    .minimumScaleFactor(0.7)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 18)
                    .padding(.top, 18)
            }
        case .recording:
            HStack {
                Spacer()
                Text("\(viewModel.countdown)")
                    .font(PingFont.numeric)
                    .foregroundStyle(.white)
                    .shadow(radius: 4)
                    .padding(8)
            }
        case .reviewing:
            HintCapsuleView(text: "↵ 보내기 · ⌫ 다시 · Esc")
                .padding(.top, 10)
        case .failed(let message):
            Text(message)
                .font(PingFont.caption)
                .foregroundStyle(Color.yellow)
                .lineLimit(2)
                .minimumScaleFactor(0.7)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 16)
                .padding(.top, 18)
        case .uploading:
            EmptyView()
        }
    }

    @ViewBuilder private var bottomOverlay: some View {
        switch viewModel.state {
        case .idle:
            PartnerPicker(appState: appState, selectedRoomIds: $selectedRoomIds, isExpanded: $pickerExpanded)
                .padding(.bottom, 10)
        case .reviewing:
            PartnerPicker(appState: appState, selectedRoomIds: $selectedRoomIds, isExpanded: $pickerExpanded)
                .padding(.bottom, 10)
        case .uploading:
            Text("전송 중...")
                .font(PingFont.caption)
                .foregroundStyle(.white)
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background {
                    Capsule()
                        .fill(PingDesign.Surface.rowFill.opacity(0.84))
                        .pingGlassEffect()
                        .overlay {
                            Capsule()
                                .strokeBorder(PingDesign.Surface.strongHairline.opacity(0.48), lineWidth: 0.8)
                        }
                }
                .padding(.bottom, 12)
        default:
            EmptyView()
        }
    }

    private func installKeyMonitor() {
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            guard event.window is MirrorWindow else {
                return event
            }

            switch event.keyCode {
            case 36: // Return
                handleReturnKey()
                return nil
            case 51: // Delete/Backspace
                handleBackspaceKey()
                return nil
            case 53: // Escape
                if case .reviewing(let tempURL) = viewModel.state {
                    try? FileManager.default.removeItem(at: tempURL)
                }
                viewModel.reset()
                onClose()
                return nil
            case 48: // Tab
                if let next = appState.cycleToNextPartner(currentRoomId: singleSelectedRoomId),
                   let id = next.id {
                    selectedRoomIds = [id]
                    appState.sendMode = .singlePartner
                }
                return nil
            case 18, 19, 20, 21, 23, 22, 26, 28, 25:
                if let index = Self.numericKeyIndex(for: event.keyCode),
                   let room = appState.selectPartner(at: index),
                   let id = room.id {
                    selectedRoomIds = [id]
                    appState.sendMode = .singlePartner
                }
                return nil
            case 29 where captureMode == .screenFace
                && event.modifierFlags.contains(.option)
                && allowsViewportEditing:
                viewport.reset()
                return nil
            case 29, 0:
                selectedRoomIds = Set(activeRooms.compactMap(\.id))
                appState.sendMode = .allPartners
                return nil
            default:
                return event
            }
        }
    }

    private func installViewportMonitors() {
        guard captureMode == .screenFace else { return }

        let mask: NSEvent.EventTypeMask = .scrollWheel
        localViewportMonitor = NSEvent.addLocalMonitorForEvents(matching: mask) { event in
            guard event.window is MirrorWindow else { return event }
            return handleViewportEvent(event) ? nil : event
        }
        globalViewportMonitor = NSEvent.addGlobalMonitorForEvents(matching: mask) { event in
            handleViewportEvent(event)
        }
        viewportTrackingTask = Task { @MainActor in
            while !Task.isCancelled {
                trackViewportToPointerIfNeeded()
                try? await Task.sleep(for: .milliseconds(33))
            }
        }
    }

    private func removeViewportMonitors() {
        if let localViewportMonitor {
            NSEvent.removeMonitor(localViewportMonitor)
            self.localViewportMonitor = nil
        }
        if let globalViewportMonitor {
            NSEvent.removeMonitor(globalViewportMonitor)
            self.globalViewportMonitor = nil
        }
        viewportTrackingTask?.cancel()
        viewportTrackingTask = nil
    }

    @discardableResult
    private func handleViewportEvent(_ event: NSEvent) -> Bool {
        guard allowsViewportEditing,
              event.modifierFlags.contains(.option) else {
            return false
        }

        switch event.type {
        case .scrollWheel:
            let delta = ScreenCaptureViewport.zoomAdjustment(
                scrollingDeltaY: event.scrollingDeltaY,
                precise: event.hasPreciseScrollingDeltas
            )
            guard delta != 0 else { return false }
            viewport.adjustZoom(by: delta)
            viewport.moveCenter(toScreenPoint: NSEvent.mouseLocation, in: captureScreenFrame)
            return true
        default:
            return false
        }
    }

    private func trackViewportToPointerIfNeeded() {
        guard allowsViewportEditing,
              NSEvent.modifierFlags.contains(.option) else {
            return
        }
        viewport.moveCenter(toScreenPoint: NSEvent.mouseLocation, in: captureScreenFrame)
    }

    private func handleReturnKey() {
        switch viewModel.state {
        case .idle, .failed:
            Task { await startRecording() }
        case .reviewing(let url):
            Task { await uploadReviewedClip(url: url) }
        case .recording, .uploading:
            break
        }
    }

    private func handleBackspaceKey() {
        if case .reviewing(let url) = viewModel.state {
            try? FileManager.default.removeItem(at: url)
            ClientEventService.shared.log("redo_used")
            Task { await startRecording() }
        }
    }

    private static func numericKeyIndex(for keyCode: UInt16) -> Int? {
        [18: 1, 19: 2, 20: 3, 21: 4, 23: 5, 22: 6, 26: 7, 28: 8, 25: 9][keyCode]
    }

    private func startRecording() async {
        switch viewModel.state {
        case .idle, .reviewing:
            break
        case .failed:
            viewModel.reset()
        case .recording, .uploading:
            return
        }

        if !camera.isReady {
            await camera.start()
            if !camera.isReady {
                viewModel.state = .failed(camera.lastError ?? "카메라 준비 중")
                return
            }
        }

        if targetsResolvingFailed() { return }

        viewModel.state = .recording
        viewModel.countdown = 3

        await camera.prepareAudioForRecording()
        // Audio configuration may briefly destabilize session; wait for first frame to land.
        try? await Task.sleep(for: .milliseconds(150))
        let countdownTask = Task { @MainActor in
            try? await Task.sleep(for: .seconds(1))
            viewModel.countdown = 2
            try? await Task.sleep(for: .seconds(1))
            viewModel.countdown = 1
        }

        do {
            let recordedURL: URL
            switch captureMode {
            case .faceOnly:
                let recorder = VideoRecorder(output: camera.movieOutput)
                recordedURL = try await recorder.recordClip()
                lastRecordedAspect = 1.0
            case .screenFace:
                let screen = captureScreen
                await screenCapture.startRecording(on: screen)
                let recorder = ScreenFaceRecorder()
                let out = try await recorder.record(
                    screenManager: screenCapture,
                    cameraSession: camera.session,
                    screenSize: captureScreenFrame.size,
                    viewport: viewport
                )
                recordedURL = out.url
                lastRecordedAspect = out.aspectRatio
                await screenCapture.startPreview(on: screen)
            }
            countdownTask.cancel()
            viewModel.enterReviewing(url: recordedURL)
        } catch {
            countdownTask.cancel()
            viewModel.state = .failed(error.localizedDescription)
        }
    }

    @discardableResult
    private func targetsResolvingFailed() -> Bool {
        if currentTargets().isEmpty {
            viewModel.state = .failed("파트너 없음")
            return true
        }
        return false
    }

    private func currentTargets() -> [Room] {
        activeRooms.filter { room in
            guard let id = room.id else { return false }
            return selectedRoomIds.contains(id)
        }
    }

    private func uploadReviewedClip(url: URL) async {
        viewModel.beginUpload()

        let origin = windowOrigin()
        let displayFrame = NSScreen.main?.frame ?? captureScreenFrame
        let centerX = origin.x + previewSize.width / 2
        let centerY = origin.y + previewSize.height / 2
        let position = ScreenCoordinates.normalize(
            point: NSPoint(x: centerX, y: centerY),
            in: displayFrame
        )

        do {
            try await onSend(url, position, currentTargets(), captureMode, lastRecordedAspect)
            try? await Task.sleep(for: .milliseconds(300))
            onClose()
            viewModel.reset()
            appState.sendMode = .singlePartner
        } catch {
            viewModel.state = .failed(error.localizedDescription)
        }
    }

    private var activeRooms: [Room] {
        appState.rooms.filter { room in
            room.id != nil && room.memberUids.count >= RoomLimits.minSendableMembers
        }
    }

    private var singleSelectedRoomId: String? {
        selectedRoomIds.count == 1 ? selectedRoomIds.first : nil
    }

    private var captureScreen: NSScreen {
        NSScreen.screens.first { $0.frame == captureScreenFrame }
            ?? NSScreen.main
            ?? NSScreen.screens.first!
    }

    private var allowsViewportEditing: Bool {
        guard captureMode == .screenFace else { return false }
        switch viewModel.state {
        case .idle, .failed:
            return true
        case .recording, .reviewing, .uploading:
            return false
        }
    }

    private var showsViewportBadge: Bool {
        allowsViewportEditing && viewport.zoom > ScreenCaptureViewport.minimumZoom + 0.01
    }

    private func reconcileSelectedRooms() {
        let activeIds = Set(activeRooms.compactMap(\.id))
        selectedRoomIds.formIntersection(activeIds)

        if selectedRoomIds.isEmpty,
           let defaultRoomId = appState.defaultRoom?.id,
           activeIds.contains(defaultRoomId) {
            selectedRoomIds = [defaultRoomId]
        }

        updateSendMode()
    }

    private func updateSendMode() {
        let activeIds = Set(activeRooms.compactMap(\.id))
        let selectedCount = selectedRoomIds.intersection(activeIds).count

        if selectedCount >= 2 && selectedCount == activeIds.count {
            appState.sendMode = .allPartners
        } else if selectedCount >= 2 {
            appState.sendMode = .selectedRooms
        } else {
            appState.sendMode = .singlePartner
        }
    }

    private var showsRainbowBorder: Bool {
        switch viewModel.state {
        case .idle, .reviewing:
            return currentTargets().count > 1
        case .uploading:
            return true
        case .recording, .failed:
            return false
        }
    }

    private var borderColor: Color {
        switch viewModel.state {
        case .idle, .reviewing, .uploading:
            return .white.opacity(0.30)
        case .recording:
            return Color(.sRGB, red: 1.0, green: 0.231, blue: 0.188, opacity: 1)
        case .failed:
            return Color(.sRGB, red: 1.0, green: 0.8, blue: 0, opacity: 1)
        }
    }

    private var borderWidth: CGFloat {
        switch viewModel.state {
        case .idle, .reviewing, .uploading:
            return 1
        case .recording, .failed:
            return 2
        }
    }
}

import AVKit

struct ReviewLoopPlayerView: NSViewRepresentable {
    let url: URL

    func makeNSView(context: Context) -> PlayerNSView {
        let view = PlayerNSView()
        view.configure(url: url)
        return view
    }

    func updateNSView(_ nsView: PlayerNSView, context: Context) {}

    final class PlayerNSView: NSView {
        private var player: AVPlayer?
        private var playerLayer: AVPlayerLayer?
        nonisolated(unsafe) private var observer: NSObjectProtocol?

        override init(frame: NSRect) {
            super.init(frame: frame)
            setup()
        }

        required init?(coder: NSCoder) {
            super.init(coder: coder)
            setup()
        }

        func configure(url: URL) {
            let item = AVPlayerItem(url: url)
            let player = AVPlayer(playerItem: item)
            player.isMuted = false
            self.player = player

            let layer = AVPlayerLayer(player: player)
            layer.videoGravity = .resizeAspectFill
            layer.frame = bounds
            self.layer?.addSublayer(layer)
            self.playerLayer = layer

            observer = NotificationCenter.default.addObserver(
                forName: .AVPlayerItemDidPlayToEndTime,
                object: item,
                queue: .main
            ) { [weak player] _ in
                player?.seek(to: .zero)
                player?.play()
            }

            player.play()
        }

        override func layout() {
            super.layout()
            playerLayer?.frame = bounds
        }

        private func setup() {
            wantsLayer = true
            layer = CALayer()
        }

        deinit {
            if let observer {
                NotificationCenter.default.removeObserver(observer)
            }
        }
    }
}

struct HintCapsuleView: View {
    let text: String
    var maxWidth: CGFloat = 156
    @State private var opacity: Double = 1.0

    var body: some View {
        Text(text)
            .font(.system(size: 11, weight: .medium))
            .foregroundStyle(.white)
            .lineLimit(1)
            .minimumScaleFactor(0.82)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .frame(maxWidth: maxWidth)
            .background {
                Capsule()
                    .fill(Color.black.opacity(0.50))
            }
            .opacity(opacity)
            .onAppear {
                opacity = 1.0
                withAnimation(.easeOut(duration: 0.5).delay(2.0)) {
                    opacity = 0
                }
            }
    }
}

struct ViewportZoomBadge: View {
    let zoom: CGFloat

    var body: some View {
        Text("\(zoom, specifier: "%.1f")× · ⌥0 초기화")
            .font(.system(size: 11, weight: .semibold, design: .rounded))
            .foregroundStyle(.white)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background {
                Capsule()
                    .fill(Color.black.opacity(0.58))
                    .overlay {
                        Capsule()
                            .strokeBorder(Color.white.opacity(0.22), lineWidth: 0.8)
                    }
            }
    }
}

struct ScreenFacePreview: View {
    @ObservedObject var screenCapture: ScreenCaptureManager
    @ObservedObject var camera: CameraManager
    let viewport: ScreenCaptureViewport

    var body: some View {
        GeometryReader { proxy in
            let diameter = ScreenFaceLayout.faceDiameter(in: proxy.size)
            let padding = ScreenFaceLayout.padding(in: proxy.size)

            ZStack(alignment: .bottomTrailing) {
                ScreenLiveImageView(screenCapture: screenCapture, viewport: viewport)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                CameraPreviewView(session: camera.session)
                    .frame(width: diameter, height: diameter)
                    .clipShape(Circle())
                    .padding(padding)
                    .allowsHitTesting(false)
            }
            .frame(width: proxy.size.width, height: proxy.size.height)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

struct ScreenLiveImageView: View {
    @ObservedObject var screenCapture: ScreenCaptureManager
    let viewport: ScreenCaptureViewport
    @State private var nsImage: NSImage?

    var body: some View {
        ZStack {
            if let nsImage {
                Image(nsImage: nsImage)
                    .resizable()
                    .scaledToFill()
            } else {
                Color.black.opacity(0.15)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .clipped()
        .allowsHitTesting(false)
        .onReceive(screenCapture.$latestFrame.compactMap { $0 }) { frame in
            let ctx = CIContext()
            let cropped = viewport.cropped(frame)
            if let cg = ctx.createCGImage(cropped, from: cropped.extent) {
                nsImage = NSImage(cgImage: cg, size: .zero)
            }
        }
    }
}
