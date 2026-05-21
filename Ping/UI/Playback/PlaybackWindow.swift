import AppKit
import SwiftUI

@MainActor
final class PlaybackWindow: NSWindow {
    static let pausedTimeoutSeconds: Double = 10
    var pingWindowId = UUID()

    private let captureMode: CaptureMode
    private let videoAspectRatio: Double?
    private let controllerBox = PlaybackView.ControllerBox()
    private var keyMonitor: Any?
    private var expandedWindow: ExpandedPlaybackWindow?
    private var timeoutTask: Task<Void, Never>?
    private var replayObserver: NSObjectProtocol?
    private let onDone: @MainActor @Sendable () -> Void
    private let onFirstPlayEnd: @MainActor @Sendable () -> Void

    static func size(for mode: CaptureMode, aspectRatio: Double?, on screen: NSScreen) -> NSSize {
        switch mode {
        case .faceOnly:
            return NSSize(width: 200, height: 200)
        case .screenFace:
            let aspect = aspectRatio ?? (screen.frame.width / screen.frame.height)
            let longSide: CGFloat = 480
            if aspect >= 1 {
                return NSSize(width: longSide, height: (longSide / aspect).rounded())
            } else {
                return NSSize(width: (longSide * aspect).rounded(), height: longSide)
            }
        }
    }

    init(
        videoURL: URL,
        mode: CaptureMode,
        aspectRatio: Double?,
        atScreenPoint origin: NSPoint,
        screen: NSScreen,
        onFirstPlayEnd: @escaping @MainActor @Sendable () -> Void,
        onDone: @escaping @MainActor @Sendable () -> Void
    ) {
        self.captureMode = mode
        self.videoAspectRatio = aspectRatio
        self.onDone = onDone
        self.onFirstPlayEnd = onFirstPlayEnd

        let size = Self.size(for: mode, aspectRatio: videoAspectRatio, on: screen)
        super.init(
            contentRect: NSRect(origin: origin, size: size),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        isOpaque = false
        backgroundColor = .clear
        level = .floating
        hasShadow = false
        ignoresMouseEvents = true
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        isReleasedWhenClosed = false

        let shape = Self.shape(for: mode)
        let root = ZStack {
            PlaybackView(url: videoURL, onFirstPlayEnd: { [weak self] in
                self?.handleFirstPlayEnd()
            }, controllerBox: controllerBox)
            .clipShape(shape)

            shape.stroke(Color.white.opacity(0.30), lineWidth: 1)
        }
        .frame(width: size.width, height: size.height)

        let host = NSHostingView(rootView: AnyView(root))
        host.frame = NSRect(origin: .zero, size: size)
        contentView = host
        alphaValue = 0
    }

    private static func shape(for mode: CaptureMode) -> AnyShape {
        switch mode {
        case .faceOnly: return AnyShape(Circle())
        case .screenFace: return AnyShape(RoundedRectangle(cornerRadius: 16))
        }
    }

    func fadeIn() {
        makeKeyAndOrderFront(nil)
        installKeyMonitor()
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.20
            animator().alphaValue = 1.0
        }
    }

    private func installKeyMonitor() {
        if keyMonitor != nil { return }
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self, event.window === self else { return event }
            switch event.keyCode {
            case 36: // Return
                self.handleReplay()
                return nil
            case 49: // Space
                self.handleExpand()
                return nil
            case 53: // Escape
                self.handleClose()
                return nil
            default:
                return event
            }
        }
    }

    private func handleExpand() {
        ClientEventService.shared.log("ping_expanded")
        guard let player = controllerBox.player, let screen = self.screen ?? NSScreen.main else { return }
        let aspect: Double
        switch captureMode {
        case .faceOnly:
            aspect = 1.0
        case .screenFace:
            aspect = videoAspectRatio ?? 1.0
        }
        let expanded = ExpandedPlaybackWindow(
            player: player,
            aspectRatio: aspect,
            on: screen,
            onDismiss: { [weak self] in
                self?.expandedWindow = nil
                self?.makeKeyAndOrderFront(nil)
            }
        )
        self.expandedWindow = expanded
        self.orderOut(nil)
        expanded.present()
    }

    private func handleFirstPlayEnd() {
        onFirstPlayEnd()
        startTimeoutCountdown()
    }

    private func handleReplay() {
        ClientEventService.shared.log("ping_replayed")
        timeoutTask?.cancel()
        controllerBox.replay()
        startReplayEndObserver()
    }

    private func startReplayEndObserver() {
        if let replayObserver {
            NotificationCenter.default.removeObserver(replayObserver)
        }
        guard let item = controllerBox.player?.currentItem else { return }
        replayObserver = NotificationCenter.default.addObserver(
            forName: .AVPlayerItemDidPlayToEndTime,
            object: item,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.controllerBox.player?.pause()
                self?.startTimeoutCountdown()
            }
        }
    }

    private func startTimeoutCountdown() {
        timeoutTask?.cancel()
        timeoutTask = Task { @MainActor in
            try? await Task.sleep(for: .seconds(Self.pausedTimeoutSeconds))
            guard !Task.isCancelled else { return }
            handleClose()
        }
    }

    private func handleClose() {
        timeoutTask?.cancel()
        if let keyMonitor {
            NSEvent.removeMonitor(keyMonitor)
            self.keyMonitor = nil
        }
        if let replayObserver {
            NotificationCenter.default.removeObserver(replayObserver)
            self.replayObserver = nil
        }
        fadeOutAndClose()
    }

    private func fadeOutAndClose() {
        NSAnimationContext.runAnimationGroup({ context in
            context.duration = 0.30
            animator().alphaValue = 0
        }, completionHandler: { [weak self] in
            Task { @MainActor in
                self?.orderOut(nil)
                self?.onDone()
            }
        })
    }
}
