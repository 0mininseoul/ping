import SwiftUI

struct GlassButton: View {
    @Environment(\.isEnabled) private var isEnabled
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var isHovering = false

    let title: String
    let isPrimary: Bool
    let action: () -> Void

    init(_ title: String, isPrimary: Bool = false, action: @escaping () -> Void) {
        self.title = title
        self.isPrimary = isPrimary
        self.action = action
    }

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(PingFont.label)
                .foregroundStyle(textColor)
                .lineLimit(1)
                .minimumScaleFactor(0.82)
                .padding(.horizontal, isPrimary ? 24 : 16)
                .padding(.vertical, isPrimary ? 10 : 8)
                .frame(minWidth: isPrimary ? 118 : nil, minHeight: isPrimary ? 40 : nil)
                .contentShape(Capsule(style: .continuous))
                .background {
                    capsuleBackground
                }
        }
        .buttonStyle(.plain)
        .scaleEffect(isInteractiveHovering ? 1.018 : 1)
        .offset(y: isInteractiveHovering ? -1 : 0)
        .animation(reduceMotion ? nil : PingDesign.Motion.buttonHover, value: isInteractiveHovering)
        .onHover { hovering in
            isHovering = hovering
        }
    }

    private var textColor: Color {
        if isPrimary {
            return Color.white.opacity(isEnabled ? 0.96 : 0.54)
        }
        return Color.primary.opacity(isEnabled ? 0.86 : 0.42)
    }

    private var isInteractiveHovering: Bool {
        isEnabled && isHovering
    }

    @ViewBuilder
    private var capsuleBackground: some View {
        if isPrimary {
            Capsule(style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [
                            PingDesign.ColorToken.accent.opacity(isEnabled ? 0.90 : 0.16),
                            PingDesign.ColorToken.accent.opacity(isEnabled ? 0.70 : 0.10)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .overlay {
                    Capsule(style: .continuous)
                        .fill(
                            LinearGradient(
                                colors: [
                                    Color.white.opacity(isEnabled ? 0.24 : 0.07),
                                    Color.clear
                                ],
                                startPoint: .top,
                                endPoint: .center
                            )
                        )
                }
                .overlay {
                    Capsule(style: .continuous)
                        .strokeBorder(
                            LinearGradient(
                                colors: [
                                    Color.white.opacity(isEnabled ? (isInteractiveHovering ? 0.58 : 0.52) : 0.14),
                                    Color.white.opacity(isEnabled ? 0.14 : 0.05)
                                ],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ),
                            lineWidth: 0.8
                        )
                }
                .pingShadow(isEnabled ? PingDesign.Shadow.accent : PingDesign.Shadow.none)
        } else {
            Capsule(style: .continuous)
                .fill(stableSecondaryFill)
                .overlay {
                    Capsule(style: .continuous)
                        .strokeBorder(
                            LinearGradient(
                                colors: [
                                    PingDesign.Surface.strongHairline.opacity(isEnabled ? (isInteractiveHovering ? 0.82 : 0.70) : 0.18),
                                    Color.primary.opacity(isEnabled ? 0.08 : 0.03)
                                ],
                                startPoint: .top,
                                endPoint: .bottom
                            ),
                            lineWidth: 0.8
                        )
                }
                .pingShadow(isEnabled ? PingDesign.Shadow.control : PingDesign.Shadow.none)
        }
    }

    private var stableSecondaryFill: LinearGradient {
        LinearGradient(
            colors: [
                PingDesign.Surface.chipFill.opacity(isEnabled ? (isInteractiveHovering ? 0.98 : 0.94) : 0.36),
                PingDesign.Surface.panelFill.opacity(isEnabled ? 0.90 : 0.28)
            ],
            startPoint: .top,
            endPoint: .bottom
        )
    }
}
