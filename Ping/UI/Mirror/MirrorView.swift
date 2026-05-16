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
            CameraPreviewView(session: camera.session)
                .clipShape(Circle())

            if appState.sendMode == .allPartners, case .idle = viewModel.state {
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
        .shadow(color: .black.opacity(0.25), radius: 24, x: 0, y: 16)
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
            EmptyView()
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
                    Capsule().glassEffect()
                }
                .padding(.bottom, 12)
        default:
            EmptyView()
        }
    }

    private func installKeyMonitor() {
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
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
        guard case .idle = viewModel.state else { return }

        let targets: [Room]
        switch appState.sendMode {
        case .singlePartner:
            guard let room = currentRoom() else {
                viewModel.state = .failed("파트너 없음")
                return
            }
            targets = [room]
        case .allPartners:
            targets = appState.rooms.filter { $0.memberUids.count == 2 }
            guard !targets.isEmpty else {
                viewModel.state = .failed("파트너 없음")
                return
            }
        }

        viewModel.state = .recording
        viewModel.countdown = 2

        let recorder = VideoRecorder(output: camera.movieOutput)
        let countdownTask = Task { @MainActor in
            try? await Task.sleep(for: .seconds(1))
            viewModel.countdown = 1
        }

        do {
            let tempURL = try await recorder.recordTwoSeconds()
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

    private var borderColor: Color {
        switch viewModel.state {
        case .idle, .uploading:
            return .white.opacity(0.30)
        case .recording:
            return Color(.sRGB, red: 1.0, green: 0.231, blue: 0.188, opacity: 1)
        case .failed:
            return Color(.sRGB, red: 1.0, green: 0.8, blue: 0, opacity: 1)
        }
    }

    private var borderWidth: CGFloat {
        switch viewModel.state {
        case .idle, .uploading:
            return 1
        case .recording, .failed:
            return 2
        }
    }
}
