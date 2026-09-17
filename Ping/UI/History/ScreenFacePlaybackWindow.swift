import AppKit
import AVFoundation
import Combine
import SwiftUI

/// Compatibility values kept for the RoomDetailView callback contract. The old
/// overlay no longer consumes an anchor; the floating player is positioned from
/// the room window instead.
struct ScreenFaceExpansionAnchor: Equatable {
    let messageId: String
    let globalFrame: CGRect
}

struct ScreenFaceExpansionContext {
    let message: VideoMessage
    let isMine: Bool
    let archivePeerName: String
    let cacheService: HistoryCacheService
    let controller: InlinePlayerController
}

enum ScreenFacePlaybackSizing {
    static let targetWidth: CGFloat = 600
    static let screenMargin: CGFloat = 32
    static let minimumAspectRatio: CGFloat = 0.5
    static let maximumAspectRatio: CGFloat = 3.0
    static let fallbackAspectRatio: CGFloat = 1.78

    static func clampedAspectRatio(_ aspectRatio: Double?) -> CGFloat {
        guard let aspectRatio,
              aspectRatio.isFinite,
              aspectRatio > 0 else {
            return fallbackAspectRatio
        }

        return min(max(CGFloat(aspectRatio), minimumAspectRatio), maximumAspectRatio)
    }

    static func size(aspectRatio: Double?, visibleFrame: CGRect) -> CGSize {
        let aspect = clampedAspectRatio(aspectRatio)
        let target = CGSize(width: targetWidth, height: targetWidth / aspect)
        let available = visibleFrame.insetBy(dx: screenMargin, dy: screenMargin)

        guard available.width > 0, available.height > 0 else {
            return target
        }

        let scale = min(
            1,
            available.width / target.width,
            available.height / target.height
        )
        return CGSize(width: target.width * scale, height: target.height * scale)
    }

    static func origin(
        size: CGSize,
        visibleFrame: CGRect,
        parentFrame: CGRect?
    ) -> CGPoint {
        let center = parentFrame.map { CGPoint(x: $0.midX, y: $0.midY) }
            ?? CGPoint(x: visibleFrame.midX, y: visibleFrame.midY)
        let preferred = CGPoint(
            x: center.x - size.width / 2,
            y: center.y - size.height / 2
        )
        return WindowPositioning.visibleOrigin(
            preferred: preferred,
            windowSize: size,
            in: visibleFrame
        )
    }
}

@MainActor
final class ScreenFacePlaybackController: ObservableObject {
    weak var player: AVPlayer?

    func replay() {
        player?.seek(to: .zero)
        player?.play()
    }
}

@MainActor
final class ScreenFacePlaybackWindow: NSWindow {
    let messageId: String

    private let controller = ScreenFacePlaybackController()
    private weak var roomWindow: NSWindow?
    private let onDismiss: @MainActor @Sendable () -> Void
    private var keyMonitor: Any?
    private var parentCloseObserver: NSObjectProtocol?
    private var isClosing = false

    init(
        context: ScreenFaceExpansionContext,
        parentWindow: NSWindow?,
        onDismiss: @escaping @MainActor @Sendable () -> Void
    ) {
        self.messageId = context.message.id ?? context.message.videoId
        self.roomWindow = parentWindow
        self.onDismiss = onDismiss

        let screen = roomWindow?.screen ?? NSScreen.main ?? NSScreen.screens.first
        let visibleFrame = screen?.visibleFrame ?? CGRect(x: 0, y: 0, width: 1_280, height: 800)
        let size = ScreenFacePlaybackSizing.size(
            aspectRatio: context.message.aspectRatio,
            visibleFrame: visibleFrame
        )
        let origin = ScreenFacePlaybackSizing.origin(
            size: size,
            visibleFrame: visibleFrame,
            parentFrame: roomWindow?.frame
        )

        super.init(
            contentRect: NSRect(origin: origin, size: size),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )

        isOpaque = false
        backgroundColor = .clear
        level = .floating
        hasShadow = true
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        isReleasedWhenClosed = false
        ignoresMouseEvents = false

        let content = ScreenFacePlaybackContent(
            message: context.message,
            isMine: context.isMine,
            archivePeerName: context.archivePeerName,
            cacheService: context.cacheService,
            controller: controller
        )
        let host = NSHostingView(rootView: content)
        host.frame = NSRect(origin: .zero, size: size)
        host.autoresizingMask = [.width, .height]
        contentView = host

        if let parentWindow {
            parentCloseObserver = NotificationCenter.default.addObserver(
                forName: NSWindow.willCloseNotification,
                object: parentWindow,
                queue: .main
            ) { [weak self] _ in
                Task { @MainActor in
                    self?.close()
                }
            }
        }
    }

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }

    func present() {
        installKeyMonitor()
        ForegroundPresenter.present(self)
    }

    override func close() {
        guard !isClosing else { return }
        isClosing = true
        removeKeyMonitor()
        if let parentCloseObserver {
            NotificationCenter.default.removeObserver(parentCloseObserver)
            self.parentCloseObserver = nil
        }
        super.close()
        onDismiss()
    }

    func replay() {
        guard !isClosing else { return }
        handleReplay()
    }

    private func installKeyMonitor() {
        guard keyMonitor == nil else { return }
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self, event.window === self else { return event }
            switch event.keyCode {
            case 53: // Escape
                self.close()
                return nil
            case 36: // Return
                self.handleReplay()
                return nil
            default:
                return event
            }
        }
    }

    private func removeKeyMonitor() {
        if let keyMonitor {
            NSEvent.removeMonitor(keyMonitor)
            self.keyMonitor = nil
        }
    }

    private func handleReplay() {
        controller.replay()
    }
}

private struct ScreenFacePlaybackContent: View {
    let message: VideoMessage
    let isMine: Bool
    let archivePeerName: String
    let cacheService: HistoryCacheService
    @ObservedObject var controller: ScreenFacePlaybackController

    @State private var localURL: URL?
    @State private var error: String?

    var body: some View {
        Group {
            if let localURL {
                ScreenFacePlaybackPlayerBox(url: localURL, controller: controller)
            } else if let error {
                VStack(spacing: 8) {
                    Image(systemName: "exclamationmark.triangle")
                        .font(.title2)
                        .foregroundStyle(.secondary)
                    Text(error)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 24)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ProgressView()
                    .controlSize(.large)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .background(Color.black.opacity(0.92))
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(Color.white.opacity(0.30), lineWidth: 1)
        }
        .task { await load() }
    }

    private func load() async {
        guard let id = message.id else {
            error = "영상 정보를 찾을 수 없어요."
            return
        }

        if let cached = cacheService.cachedFile(roomId: message.roomId, messageId: id) {
            localURL = cached
            return
        }
        if let archived = archivedVideoURL() {
            localURL = archived
            return
        }

        do {
            let storage = StorageService()
            let tempURL = try await storage.downloadVideo(remotePath: message.videoUrl)
            localURL = try cacheService.storeDownload(
                roomId: message.roomId,
                messageId: id,
                sourceTemp: tempURL
            )
        } catch let err {
            let description = err.localizedDescription
            if description.contains("Object not found") || description.contains("404") || description.contains("not found") {
                error = "영상이 만료되어 더 이상 재생할 수 없어요."
            } else {
                error = "영상 로드 실패: \(description)"
            }
            NSLog("ScreenFacePlaybackWindow load failed: \(err) — message=\(id) videoUrl=\(message.videoUrl)")
        }
    }

    private func archivedVideoURL() -> URL? {
        guard let createdAt = message.createdAt else { return nil }
        guard isMine || message.allowsLocalSave else { return nil }
        let direction: LocalArchive.Direction = isMine ? .sent : .received
        return LocalArchive.existingVideoURL(
            direction: direction,
            nickname: archivePeerName,
            date: createdAt
        )
    }
}

private struct ScreenFacePlaybackPlayerBox: NSViewRepresentable {
    let url: URL
    @ObservedObject var controller: ScreenFacePlaybackController

    func makeNSView(context: Context) -> PlayerContainerView {
        let container = PlayerContainerView()
        let item = AVPlayerItem(url: url)
        let player = AVPlayer(playerItem: item)
        let layer = AVPlayerLayer(player: player)
        layer.videoGravity = .resizeAspect
        container.configure(playerLayer: layer)
        controller.player = player

        context.coordinator.statusObserver = item.observe(\.status, options: [.new]) { item, _ in
            NSLog("ScreenFacePlaybackPlayer status=\(item.status.rawValue) error=\(String(describing: item.error)) url=\(url)")
        }
        context.coordinator.endObserver = NotificationCenter.default.addObserver(
            forName: .AVPlayerItemDidPlayToEndTime,
            object: item,
            queue: .main
        ) { [weak player] _ in
            player?.pause()
        }
        context.coordinator.failureObserver = NotificationCenter.default.addObserver(
            forName: AVPlayerItem.failedToPlayToEndTimeNotification,
            object: item,
            queue: .main
        ) { note in
            NSLog("ScreenFacePlaybackPlayer failedToPlayToEnd: \(note.userInfo ?? [:]) url=\(url)")
        }
        return container
    }

    func updateNSView(_ nsView: PlayerContainerView, context: Context) {}

    func makeCoordinator() -> Coordinator { Coordinator() }

    final class Coordinator {
        var statusObserver: NSKeyValueObservation?
        var endObserver: NSObjectProtocol?
        var failureObserver: NSObjectProtocol?

        deinit {
            statusObserver?.invalidate()
            if let endObserver { NotificationCenter.default.removeObserver(endObserver) }
            if let failureObserver { NotificationCenter.default.removeObserver(failureObserver) }
        }
    }

    final class PlayerContainerView: NSView {
        private var playerLayer: AVPlayerLayer?
        private var didStartPlayback = false

        override init(frame frameRect: NSRect) {
            super.init(frame: frameRect)
            wantsLayer = true
            layer = CALayer()
        }

        required init?(coder: NSCoder) {
            super.init(coder: coder)
            wantsLayer = true
            layer = CALayer()
        }

        func configure(playerLayer: AVPlayerLayer) {
            self.playerLayer?.removeFromSuperlayer()
            self.playerLayer = playerLayer
            layer?.addSublayer(playerLayer)
            needsLayout = true
        }

        override func layout() {
            super.layout()
            playerLayer?.frame = bounds
            guard !didStartPlayback,
                  bounds.width > 8,
                  bounds.height > 8,
                  let player = playerLayer?.player else {
                return
            }

            didStartPlayback = true
            player.seek(to: .zero)
            player.play()
        }
    }
}
