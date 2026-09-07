import SwiftUI
import UIKit
import PingKit

actor ChatImageCache {
    static let shared = ChatImageCache()

    private var inflight: [String: Task<Data, Error>] = [:]
    private let diskDir: URL

    init() {
        let base = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        diskDir = base.appendingPathComponent("ping-chat-images", isDirectory: true)
        try? FileManager.default.createDirectory(at: diskDir, withIntermediateDirectories: true)
    }

    func data(for message: PingChatMessage) async throws -> Data {
        guard let mediaPath = message.mediaPath, !mediaPath.isEmpty else {
            throw PingKitError.unavailable
        }

        let url = diskDir.appendingPathComponent("\(message.id).\(message.mediaFileExtension)")
        if let cached = try? Data(contentsOf: url), !cached.isEmpty {
            return cached
        }
        if let existing = inflight[message.id] {
            return try await existing.value
        }

        let task = Task<Data, Error> {
            guard let client = await AppEnvironment.shared.makeClient() else {
                throw PingMobileError.notPaired
            }
            let data = try await client.downloadChatMedia(path: mediaPath)
            try data.write(to: url, options: .atomic)
            return data
        }
        inflight[message.id] = task
        defer { inflight[message.id] = nil }
        return try await task.value
    }
}

struct ChatImageAttachmentView: View {
    let message: PingChatMessage
    /// Handed the decoded photo so the thread can open it fullscreen, the same
    /// way tapping a ping thumbnail opens the player.
    let onOpen: (UIImage) -> Void

    @State private var image: UIImage?
    @State private var didFail = false

    private let maxWidth: CGFloat = 240
    private let maxHeight: CGFloat = 260

    var body: some View {
        ZStack {
            if let image {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFit()
                    .frame(width: displaySize.width, height: displaySize.height)
            } else if didFail {
                VStack(spacing: 6) {
                    Image(systemName: "photo")
                        .font(.title3)
                    Text("사진을 불러올 수 없음")
                        .font(.caption)
                }
                .foregroundStyle(.secondary)
            } else {
                ProgressView()
                    .controlSize(.small)
            }
        }
        .frame(width: displaySize.width, height: displaySize.height)
        .background(Color.gray.opacity(0.10))
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.06))
        )
        .contentShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .onTapGesture {
            guard let image else { return }
            onOpen(image)
        }
        .accessibilityLabel(accessibilityLabel)
        .accessibilityAddTraits(image == nil ? [] : .isButton)
        .accessibilityHint(image == nil ? "" : "전체화면으로 보기")
        .task(id: message.mediaPath) {
            await loadImage()
        }
    }

    private var displaySize: CGSize {
        guard let width = message.mediaWidth,
              let height = message.mediaHeight,
              width > 0,
              height > 0 else {
            return CGSize(width: 200, height: 160)
        }

        let scale = min(maxWidth / CGFloat(width), maxHeight / CGFloat(height))
        return CGSize(
            width: max(80, CGFloat(width) * scale),
            height: max(80, CGFloat(height) * scale)
        )
    }

    private var accessibilityLabel: String {
        guard let fileName = message.mediaFileName,
              !fileName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return "사진"
        }
        return fileName
    }

    @MainActor
    private func loadImage() async {
        guard image == nil else { return }
        do {
            let data = try await ChatImageCache.shared.data(for: message)
            image = UIImage(data: data)
            didFail = image == nil
        } catch {
            didFail = true
        }
    }
}

/// A decoded chat photo ready to fill the screen.
struct ChatImagePreview: Identifiable {
    let id: String
    let image: UIImage
    let fileName: String?
}

/// Fullscreen photo viewer — the still-image counterpart to `VideoPlayerScreen`.
/// Pinch or double-tap to zoom, drag to pan while zoomed, swipe to dismiss.
///
/// Live gesture values are `@GestureState` so SwiftUI zeroes them if a gesture is
/// cancelled rather than ended: the committed `scale`/`offset` can never drift out
/// of sync with what is on screen and strand the viewer in a state where it looks
/// unzoomed but refuses to pan or dismiss.
struct ChatImagePreviewScreen: View {
    let preview: ChatImagePreview

    @Environment(\.dismiss) private var dismiss

    @GestureState private var pinch: CGFloat = 1
    @GestureState private var drag: CGSize = .zero
    @State private var scale: CGFloat = 1
    @State private var offset: CGSize = .zero

    private let maxScale: CGFloat = 4
    private let doubleTapScale: CGFloat = 2.5
    private let dismissDistance: CGFloat = 120
    /// A pinch rarely ends exactly at fit; it lands at 1.01x, 1.03x. That is not a
    /// zoom anyone asked for — it looks identical to fit but leaves only a few
    /// points of pan travel, and it would switch a drag from "dismiss" to "pan",
    /// stranding the viewer on a photo that ignores both. Anything under this
    /// snaps back to exactly fit, and every "is this zoomed" test goes through
    /// `isZoomed` so the two can never disagree.
    private let fitSnapScale: CGFloat = 1.05
    private let track = Animation.interactiveSpring(response: 0.24, dampingFraction: 0.88)

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            // The photo spans the whole screen; the chrome above it stays inside
            // the safe area so it never sits under the status bar.
            GeometryReader { geo in
                let pan = panOffset(in: geo.size)
                Image(uiImage: preview.image)
                    .resizable()
                    .scaledToFit()
                    .frame(width: geo.size.width, height: geo.size.height)
                    .scaleEffect(renderedScale * dismissScale)
                    .offset(x: pan.width, y: pan.height + swipeTranslation)
                    .animation(track, value: drag)
                    .animation(track, value: pinch)
                    .accessibilityLabel(displayName ?? "사진")
                    .gesture(zoomGesture(in: geo.size))
                    .simultaneousGesture(panGesture(in: geo.size))
                    .onTapGesture(count: 2) { toggleZoom() }
            }
            .ignoresSafeArea()

            controls
        }
    }

    private var controls: some View {
        VStack {
            HStack(alignment: .top, spacing: 8) {
                if let displayName {
                    Text(displayName)
                        .font(.footnote.weight(.medium))
                        .foregroundStyle(.white.opacity(0.75))
                        .lineLimit(1)
                        .padding(.leading, 20)
                        .padding(.top, 24)
                }
                Spacer(minLength: 0)
                Button { dismiss() } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 30))
                        .foregroundStyle(.white.opacity(0.85))
                        .padding()
                }
                .accessibilityLabel("닫기")
            }
            Spacer()
        }
        // Fading the chrome out with the swipe keeps the close button from
        // hovering over a photo that is already on its way off screen.
        .opacity(1 - min(1, abs(swipeTranslation) / dismissDistance))
    }

    // MARK: - Gestures

    private func zoomGesture(in container: CGSize) -> some Gesture {
        MagnifyGesture()
            .updating($pinch) { value, state, _ in state = value.magnification }
            .onEnded { value in
                let next = clampedScale(scale * value.magnification)
                withAnimation(.easeOut(duration: 0.18)) {
                    scale = isZoomed(next) ? next : 1
                    offset = isZoomed(scale)
                        ? clampedOffset(offset, scale: scale, in: container)
                        : .zero
                }
            }
    }

    private func panGesture(in container: CGSize) -> some Gesture {
        DragGesture()
            .updating($drag) { value, state, _ in state = value.translation }
            .onEnded { value in
                guard !isZoomed(scale) else {
                    offset = clampedOffset(
                        CGSize(
                            width: offset.width + value.translation.width,
                            height: offset.height + value.translation.height
                        ),
                        scale: scale,
                        in: container
                    )
                    return
                }
                let travel = max(
                    abs(value.translation.height),
                    abs(value.predictedEndTranslation.height) / 2
                )
                if travel > dismissDistance { dismiss() }
            }
    }

    private func toggleZoom() {
        withAnimation(.spring(response: 0.28, dampingFraction: 0.86)) {
            if isZoomed(scale) {
                scale = 1
                offset = .zero
            } else {
                scale = doubleTapScale
            }
        }
    }

    // MARK: - Derived geometry

    private var renderedScale: CGFloat { clampedScale(scale * pinch) }

    private var isZoomed: Bool { isZoomed(renderedScale) }

    private func isZoomed(_ scale: CGFloat) -> Bool { scale > fitSnapScale }

    /// A drag only dismisses at fit scale; while zoomed it pans instead.
    private var swipeTranslation: CGFloat { isZoomed ? 0 : drag.height }

    /// Shrinks the photo slightly as the swipe progresses so the dismiss reads
    /// as "throwing it away" rather than sliding a static image.
    private var dismissScale: CGFloat {
        1 - min(1, abs(swipeTranslation) / (dismissDistance * 4)) * 0.12
    }

    private func panOffset(in container: CGSize) -> CGSize {
        guard isZoomed else { return .zero }
        return clampedOffset(
            CGSize(width: offset.width + drag.width, height: offset.height + drag.height),
            scale: renderedScale,
            in: container
        )
    }

    private func clampedScale(_ proposed: CGFloat) -> CGFloat {
        min(max(proposed, 1), maxScale)
    }

    /// The photo is drawn `scaledToFit`, so panning is only meaningful over the
    /// part of the scaled fit-rect that overflows the screen.
    private func clampedOffset(_ proposed: CGSize, scale: CGFloat, in container: CGSize) -> CGSize {
        let fitted = fittedSize(in: container)
        let limitX = max(0, (fitted.width * scale - container.width) / 2)
        let limitY = max(0, (fitted.height * scale - container.height) / 2)
        return CGSize(
            width: min(max(proposed.width, -limitX), limitX),
            height: min(max(proposed.height, -limitY), limitY)
        )
    }

    private func fittedSize(in container: CGSize) -> CGSize {
        let size = preview.image.size
        guard size.width > 0, size.height > 0, container.width > 0, container.height > 0 else {
            return container
        }
        let ratio = min(container.width / size.width, container.height / size.height)
        return CGSize(width: size.width * ratio, height: size.height * ratio)
    }

    private var displayName: String? {
        guard let fileName = preview.fileName else { return nil }
        let trimmed = fileName.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
