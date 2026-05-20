import SwiftUI
@preconcurrency import AVFoundation

struct MirrorView: View {
    @ObservedObject var camera: CameraManager
    @ObservedObject var viewModel: MirrorViewModel
    @ObservedObject var appState: AppState

    var windowOrigin: () -> NSPoint
    var onClose: () -> Void = {}
    var onSend: (URL, MirrorPosition, [Room]) async throws -> Void

    @State private var keyMonitor: Any?
    @State private var selectedRoomId: String?
    @State private var pickerExpanded = false

    var body: some View {
        ZStack {
            mirrorShadowSurface
            mirrorContent
        }
        .frame(width: 200, height: 200)
        .contentShape(Circle())
        .onAppear {
            selectedRoomId = appState.defaultRoom?.id
            installKeyMonitor()
        }
        .onDisappear {
            if let keyMonitor {
                NSEvent.removeMonitor(keyMonitor)
            }
            keyMonitor = nil
        }
    }

    private var mirrorShadowSurface: some View {
        Circle()
            .fill(PingDesign.Surface.circleFill)
            .pingShadow(PingDesign.Shadow.mirror)
    }

    private var mirrorContent: some View {
        ZStack {
            CameraPreviewView(session: camera.session)
                .clipShape(Circle())

            if showsRainbowBorder {
                RainbowBorder(lineWidth: 2)
            } else {
                Circle().strokeBorder(borderColor, lineWidth: borderWidth)
            }

            VStack {
                topOverlay
                Spacer()
                bottomOverlay
            }
        }
        .frame(width: 200, height: 200)
    }

    @ViewBuilder private var topOverlay: some View {
        switch viewModel.state {
        case .recording:
            HStack {
                Spacer()
                Text("\(viewModel.countdown)")
                    .font(PingFont.numeric)
                    .foregroundStyle(.white)
                    .shadow(radius: 4)
                    .padding(8)
            }
        case .failed(let message):
            Text(message)
                .font(PingFont.caption)
                .foregroundStyle(Color.yellow)
                .lineLimit(2)
                .minimumScaleFactor(0.7)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 16)
                .padding(.top, 18)
        default:
            if !camera.isReady {
                Text(camera.lastError ?? "카메라 준비 중")
                    .font(PingFont.caption)
                    .foregroundStyle(.white)
                    .lineLimit(2)
                    .minimumScaleFactor(0.7)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 18)
                    .padding(.top, 18)
            }
        }
    }

    @ViewBuilder private var bottomOverlay: some View {
        switch viewModel.state {
        case .idle:
            PartnerPicker(appState: appState, selectedRoomId: $selectedRoomId, isExpanded: $pickerExpanded)
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
            case 36:
                Task { await startRecording() }
                return nil
            case 53:
                onClose()
                return nil
            case 48:
                if let next = appState.cycleToNextPartner(currentRoomId: selectedRoomId) {
                    selectedRoomId = next.id
                    appState.sendMode = .singlePartner
                }
                return nil
            case 18, 19, 20, 21, 23, 22, 26, 28, 25:
                if let index = Self.numericKeyIndex(for: event.keyCode),
                   let room = appState.selectPartner(at: index) {
                    selectedRoomId = room.id
                    appState.sendMode = .singlePartner
                }
                return nil
            case 29, 0:
                appState.sendMode = .allPartners
                return nil
            default:
                return event
            }
        }
    }

    private static func numericKeyIndex(for keyCode: UInt16) -> Int? {
        [18: 1, 19: 2, 20: 3, 21: 4, 23: 5, 22: 6, 26: 7, 28: 8, 25: 9][keyCode]
    }

    private func startRecording() async {
        switch viewModel.state {
        case .idle:
            break
        case .failed:
            viewModel.reset()
        case .recording, .uploading, .reviewing:
            return
        }

        if !camera.isReady {
            await camera.start()
            if !camera.isReady {
                viewModel.state = .failed(camera.lastError ?? "카메라 준비 중")
                return
            }
        }

        let targets: [Room]
        switch appState.sendMode {
        case .singlePartner:
            guard let room = currentRoom() else {
                viewModel.state = .failed("파트너 없음")
                return
            }
            targets = [room]
        case .allPartners:
            targets = appState.rooms.filter { $0.memberUids.count >= RoomLimits.minSendableMembers }
            guard !targets.isEmpty else {
                viewModel.state = .failed("파트너 없음")
                return
            }
        }

        viewModel.state = .recording
        viewModel.countdown = 3

        await camera.prepareAudioForRecording()
        // Audio configuration may briefly destabilize session; wait for first frame to land.
        try? await Task.sleep(for: .milliseconds(150))
        let recorder = VideoRecorder(output: camera.movieOutput)
        let countdownTask = Task { @MainActor in
            try? await Task.sleep(for: .seconds(1))
            viewModel.countdown = 2
            try? await Task.sleep(for: .seconds(1))
            viewModel.countdown = 1
        }

        do {
            let tempURL = try await recorder.recordClip()
            countdownTask.cancel()
            viewModel.state = .uploading

            let origin = windowOrigin()
            let screen = NSScreen.main?.frame ?? .zero
            let center = NSPoint(x: origin.x + 100, y: origin.y + 100)
            let position = ScreenCoordinates.normalize(point: center, in: screen)

            try await onSend(tempURL, position, targets)

            try? await Task.sleep(for: .milliseconds(300))
            onClose()
            viewModel.reset()
            appState.sendMode = .singlePartner
        } catch {
            countdownTask.cancel()
            viewModel.state = .failed(error.localizedDescription)
        }
    }

    private func currentRoom() -> Room? {
        guard let selectedRoomId else { return appState.defaultRoom }
        return appState.rooms.first(where: { $0.id == selectedRoomId }) ?? appState.defaultRoom
    }

    private var showsRainbowBorder: Bool {
        switch viewModel.state {
        case .idle:
            return appState.sendMode == .allPartners
        case .uploading:
            return true
        case .recording, .failed, .reviewing:
            return false
        }
    }

    private var borderColor: Color {
        switch viewModel.state {
        case .idle, .uploading, .reviewing:
            return .white.opacity(0.30)
        case .recording:
            return Color(.sRGB, red: 1.0, green: 0.231, blue: 0.188, opacity: 1)
        case .failed:
            return Color(.sRGB, red: 1.0, green: 0.8, blue: 0, opacity: 1)
        }
    }

    private var borderWidth: CGFloat {
        switch viewModel.state {
        case .idle, .uploading, .reviewing:
            return 1
        case .recording, .failed:
            return 2
        }
    }
}
