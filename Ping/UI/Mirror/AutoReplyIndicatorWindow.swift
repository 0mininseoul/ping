import AppKit
import SwiftUI

/// 자동 얼굴 회신이 녹화 중임을 알리는 오버레이.
///
/// 원격에서 트리거되어 웹캠이 켜지는 동작이므로 본인이 알아챌 수 있어야 한다. 다만
/// 절대 포커스를 가져가지 않는다 — 0.3.66에서 자동재생 창이 활성화를 뺏어 로컬 키
/// 모니터가 이벤트를 못 받은 전례가 있다. 사용자가 하던 일은 그대로 둔다.
/// 카메라 프리뷰는 붙이지 않는다: 알림이 목적이지 거울이 목적이 아니다.
@MainActor
final class AutoReplyIndicatorWindow: NSPanel {
    private static let size = NSSize(width: 232, height: 56)
    private static let screenMargin: CGFloat = 20

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }

    init(senderNickname: String, duration: Double) {
        super.init(
            contentRect: NSRect(origin: .zero, size: Self.size),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )

        isOpaque = false
        backgroundColor = .clear
        hasShadow = true
        level = .statusBar
        ignoresMouseEvents = true
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        isMovable = false

        let host = NSHostingView(
            rootView: AutoReplyIndicatorView(senderNickname: senderNickname, duration: duration)
        )
        host.frame = NSRect(origin: .zero, size: Self.size)
        contentView = host

        positionAtTopTrailing()
    }

    private func positionAtTopTrailing() {
        guard let screen = NSScreen.main ?? NSScreen.screens.first else { return }
        let visible = screen.visibleFrame
        setFrameOrigin(
            NSPoint(
                x: visible.maxX - Self.size.width - Self.screenMargin,
                y: visible.maxY - Self.size.height - Self.screenMargin
            )
        )
    }

    func present() {
        orderFrontRegardless()
    }

    func dismiss() {
        contentView = nil
        orderOut(nil)
    }
}

private struct AutoReplyIndicatorView: View {
    let senderNickname: String
    let duration: Double

    @State private var progress: Double = 0
    @State private var isPulsing = false

    var body: some View {
        HStack(spacing: 12) {
            Circle()
                .fill(PingDesign.ColorToken.destructive)
                .frame(width: 10, height: 10)
                .opacity(isPulsing ? 0.35 : 1)
                .animation(.easeInOut(duration: 0.6).repeatForever(autoreverses: true), value: isPulsing)

            VStack(alignment: .leading, spacing: 5) {
                Text("자동 회신 녹화 중")
                    .font(.system(size: 13, weight: .semibold))

                Text("\(senderNickname)님에게 보냅니다")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 14)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .background(alignment: .bottom) {
            GeometryReader { geometry in
                Rectangle()
                    .fill(PingDesign.ColorToken.destructive)
                    .frame(width: geometry.size.width * progress, height: 2)
                    .frame(maxHeight: .infinity, alignment: .bottom)
            }
        }
        .background(
            RoundedRectangle(cornerRadius: PingDesign.Radius.row, style: .continuous)
                .fill(PingDesign.Surface.windowBase)
        )
        .clipShape(RoundedRectangle(cornerRadius: PingDesign.Radius.row, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: PingDesign.Radius.row, style: .continuous)
                .stroke(PingDesign.ColorToken.destructive, lineWidth: 2)
        )
        .onAppear {
            isPulsing = true
            withAnimation(.linear(duration: duration)) { progress = 1 }
        }
    }
}
