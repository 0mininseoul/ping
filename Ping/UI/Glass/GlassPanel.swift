import SwiftUI

struct GlassPanel<Content: View>: View {
    enum PanelShape {
        case rect(cornerRadius: CGFloat)
        case circle
    }

    let shape: PanelShape
    let content: () -> Content

    init(shape: PanelShape = .rect(cornerRadius: 16), @ViewBuilder content: @escaping () -> Content) {
        self.shape = shape
        self.content = content
    }

    var body: some View {
        content()
            .background {
                switch shape {
                case .rect(let radius):
                    RoundedRectangle(cornerRadius: radius, style: .continuous)
                        .glassEffect()
                        .overlay {
                            RoundedRectangle(cornerRadius: radius, style: .continuous)
                                .strokeBorder(Color.white.opacity(0.30), lineWidth: 1)
                        }
                case .circle:
                    Circle()
                        .glassEffect()
                        .overlay {
                            Circle().strokeBorder(Color.white.opacity(0.30), lineWidth: 1)
                        }
                }
            }
            .shadow(color: .black.opacity(0.15), radius: 24, x: 0, y: 16)
    }
}

#if DEBUG
#Preview("GlassPanel Rect") {
    GlassPanel {
        Text("Ping")
            .font(PingFont.title)
            .padding(40)
    }
    .frame(width: 300, height: 200)
    .padding()
}

#Preview("GlassPanel Circle") {
    GlassPanel(shape: .circle) {
        Color.gray.opacity(0.25)
    }
    .frame(width: 200, height: 200)
    .padding()
}
#endif
