import SwiftUI

struct GlassPanel<Content: View>: View {
    enum PanelShape {
        case rect(cornerRadius: CGFloat)
        case circle
    }

    let shape: PanelShape
    let content: () -> Content

    init(shape: PanelShape = .rect(cornerRadius: PingDesign.Radius.panel), @ViewBuilder content: @escaping () -> Content) {
        self.shape = shape
        self.content = content
    }

    var body: some View {
        content()
            .background {
                switch shape {
                case .rect(let radius):
                    RoundedRectangle(cornerRadius: radius, style: .continuous)
                        .fill(PingDesign.Surface.panelFill)
                        .overlay {
                            RoundedRectangle(cornerRadius: radius, style: .continuous)
                                .strokeBorder(PingDesign.Surface.hairline, lineWidth: 0.8)
                        }
                        .overlay {
                            RoundedRectangle(cornerRadius: radius, style: .continuous)
                                .inset(by: 1)
                                .strokeBorder(PingDesign.Surface.strongHairline.opacity(0.64), lineWidth: 0.6)
                        }
                case .circle:
                    Circle()
                        .fill(PingDesign.Surface.circleFill)
                        .overlay {
                            Circle().strokeBorder(PingDesign.Surface.strongHairline, lineWidth: 0.8)
                        }
                        .overlay {
                            Circle()
                                .inset(by: 1)
                                .strokeBorder(PingDesign.Surface.hairline, lineWidth: 0.6)
                        }
                }
            }
            .pingShadow(PingDesign.Shadow.panel)
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
