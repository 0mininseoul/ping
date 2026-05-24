import SwiftUI

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

struct ScreenFaceExpansionFrameReporter: View {
    let messageId: String
    let size: CGSize
    let onChange: (ScreenFaceExpansionAnchor?) -> Void

    var body: some View {
        Color.clear
            .frame(width: 1, height: size.height)
            .background(
                GeometryReader { proxy in
                    let frame = proxy.frame(in: .global)
                    Color.clear
                        .onAppear {
                            onChange(ScreenFaceExpansionAnchor(messageId: messageId, globalFrame: frame))
                        }
                        .onChange(of: frame) { newFrame in
                            onChange(ScreenFaceExpansionAnchor(messageId: messageId, globalFrame: newFrame))
                        }
                }
            )
            .onDisappear {
                onChange(nil)
            }
    }
}

struct ScreenFaceExpansionOverlay: View {
    let anchor: ScreenFaceExpansionAnchor?
    let context: ScreenFaceExpansionContext?

    var body: some View {
        GeometryReader { proxy in
            if let anchor,
               let context,
               context.message.id == anchor.messageId {
                let rootFrame = proxy.frame(in: .global)
                let anchorRect = CGRect(
                    x: anchor.globalFrame.minX - rootFrame.minX,
                    y: anchor.globalFrame.minY - rootFrame.minY,
                    width: anchor.globalFrame.width,
                    height: anchor.globalFrame.height
                )
                let size = InlinePlayerView.playerSize(for: context.message)

                InlinePlayerView(
                    message: context.message,
                    isMine: context.isMine,
                    archivePeerName: context.archivePeerName,
                    cacheService: context.cacheService,
                    controller: context.controller
                )
                .frame(width: size.width, height: size.height)
                .position(
                    x: Self.overlayX(anchorRect: anchorRect, size: size, containerWidth: proxy.size.width),
                    y: anchorRect.midY
                )
                .allowsHitTesting(false)
                .zIndex(10)
            }
        }
    }

    static func overlayX(anchorRect: CGRect, size: CGSize, containerWidth: CGFloat) -> CGFloat {
        let trailingEdge = min(containerWidth - 16, anchorRect.maxX)
        let proposed = trailingEdge - size.width / 2
        let minCenter = min(size.width / 2 + 16, containerWidth / 2)
        let maxCenter = max(containerWidth - size.width / 2 - 16, containerWidth / 2)
        return min(max(proposed, minCenter), maxCenter)
    }
}
