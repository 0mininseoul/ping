import AppKit
import SwiftUI

@MainActor
final class PlaybackWindow: NSWindow {
    static let size = NSSize(width: 200, height: 200)
    static let pausedTimeoutSeconds: Double = 10
    var pingWindowId = UUID()

    private let controllerBox = PlaybackView.ControllerBox()
    private var keyMonitor: Any?
    private var timeoutTask: Task<Void, Never>?
    private var replayObserver: NSObjectProtocol?
    private let onDone: @MainActor @Sendable () -> Void
    private let onFirstPlayEnd: @MainActor @Sendable () -> Void

    init(
        videoURL: URL,
        atScreenPoint origin: NSPoint,
        onFirstPlayEnd: @escaping @MainActor @Sendable () -> Void,
        onDone: @escaping @MainActor @Sendable () -> Void
    ) {
        self.onDone = onDone
        self.onFirstPlayEnd = onFirstPlayEnd

        super.init(
            contentRect: NSRect(origin: origin, size: Self.size),
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

        let root = ZStack {
            PlaybackView(url: videoURL, onFirstPlayEnd: { [weak self] in
                self?.handleFirstPlayEnd()
            }, controllerBox: controllerBox)
            .clipShape(Circle())

            Circle().strokeBorder(Color.white.opacity(0.30), lineWidth: 1)
        }
        .frame(width: Self.size.width, height: Self.size.height)

        let host = NSHostingView(rootView: AnyView(root))
        host.frame = NSRect(origin: .zero, size: Self.size)
        contentView = host
        alphaValue = 0
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
            case 53: // Escape
                self.handleClose()
                return nil
            default:
                return event
            }
        }
    }

    private func handleFirstPlayEnd() {
        onFirstPlayEnd()
        startTimeoutCountdown()
    }

    private func handleReplay() {
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
