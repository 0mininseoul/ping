import SwiftUI

enum PingDesign {
    enum ColorToken {
        // OKLCH source: light oklch(58% 0.17 248), dark oklch(72% 0.12 245).
        static let accent = adaptive(
            light: NSColor(srgbRed: 0.14, green: 0.43, blue: 0.95, alpha: 1),
            dark: NSColor(srgbRed: 0.42, green: 0.68, blue: 1.00, alpha: 1)
        )

        // OKLCH source: light oklch(66% 0.16 146), dark oklch(73% 0.13 150).
        static let success = adaptive(
            light: NSColor(srgbRed: 0.14, green: 0.58, blue: 0.32, alpha: 1),
            dark: NSColor(srgbRed: 0.38, green: 0.78, blue: 0.52, alpha: 1)
        )

        // OKLCH source: light oklch(67% 0.17 70), dark oklch(78% 0.13 78).
        static let warning = adaptive(
            light: NSColor(srgbRed: 0.72, green: 0.43, blue: 0.03, alpha: 1),
            dark: NSColor(srgbRed: 0.95, green: 0.68, blue: 0.24, alpha: 1)
        )

        // OKLCH source: light oklch(63% 0.22 29), dark oklch(70% 0.18 29).
        static let destructive = adaptive(
            light: NSColor(srgbRed: 1.00, green: 0.23, blue: 0.19, alpha: 1),
            dark: NSColor(srgbRed: 1.00, green: 0.42, blue: 0.35, alpha: 1)
        )

        // OKLCH source: light oklch(72% 0.11 220), dark oklch(68% 0.09 218).
        static let glassTint = adaptive(
            light: NSColor(srgbRed: 0.45, green: 0.74, blue: 0.95, alpha: 1),
            dark: NSColor(srgbRed: 0.33, green: 0.63, blue: 0.82, alpha: 1)
        )
    }

    enum Radius {
        static let panel: CGFloat = 18
        static let row: CGFloat = 16
        static let iconTile: CGFloat = 12
    }

    enum Surface {
        static var windowBase: Color {
            adaptive(
                light: NSColor.windowBackgroundColor,
                dark: NSColor(srgbRed: 0.055, green: 0.067, blue: 0.075, alpha: 1)
            )
        }

        static var backgroundWashLeading: Color {
            adaptive(
                light: NSColor(srgbRed: 0.74, green: 0.88, blue: 1.00, alpha: 0.34),
                dark: NSColor(srgbRed: 0.08, green: 0.14, blue: 0.22, alpha: 0.42)
            )
        }

        static var backgroundWashTrailing: Color {
            adaptive(
                light: NSColor(srgbRed: 0.91, green: 0.98, blue: 0.93, alpha: 0.28),
                dark: NSColor(srgbRed: 0.10, green: 0.14, blue: 0.15, alpha: 0.16)
            )
        }

        static var radialHighlight: Color {
            adaptive(
                light: NSColor.white.withAlphaComponent(0.58),
                dark: NSColor(srgbRed: 0.34, green: 0.48, blue: 0.58, alpha: 0.08)
            )
        }

        static var progressTrack: Color {
            adaptive(
                light: NSColor.black.withAlphaComponent(0.08),
                dark: NSColor(srgbRed: 0.78, green: 0.86, blue: 0.92, alpha: 0.12)
            )
        }

        static var rowFill: Color {
            adaptive(
                light: NSColor(srgbRed: 0.965, green: 0.985, blue: 1.000, alpha: 0.94),
                dark: NSColor(srgbRed: 0.085, green: 0.100, blue: 0.110, alpha: 0.88)
            )
        }

        static var panelFill: Color {
            adaptive(
                light: NSColor(srgbRed: 0.985, green: 0.995, blue: 1.000, alpha: 0.92),
                dark: NSColor(srgbRed: 0.095, green: 0.115, blue: 0.130, alpha: 0.84)
            )
        }

        static var inputCardFill: Color {
            adaptive(
                light: NSColor.white.withAlphaComponent(0.58),
                dark: NSColor(srgbRed: 0.092, green: 0.108, blue: 0.120, alpha: 0.92)
            )
        }

        static var inputFieldFill: Color {
            adaptive(
                light: NSColor.white.withAlphaComponent(0.66),
                dark: NSColor(srgbRed: 0.050, green: 0.064, blue: 0.078, alpha: 0.96)
            )
        }

        static var inputFieldFocusedFill: Color {
            adaptive(
                light: NSColor.white.withAlphaComponent(0.78),
                dark: NSColor(srgbRed: 0.058, green: 0.078, blue: 0.100, alpha: 0.98)
            )
        }

        static var chipFill: Color {
            adaptive(
                light: NSColor.white.withAlphaComponent(0.86),
                dark: NSColor(srgbRed: 0.100, green: 0.120, blue: 0.140, alpha: 0.86)
            )
        }

        static var circleFill: Color {
            adaptive(
                light: NSColor.white.withAlphaComponent(0.32),
                dark: NSColor(srgbRed: 0.120, green: 0.145, blue: 0.160, alpha: 0.78)
            )
        }

        static var hairline: Color {
            adaptive(
                light: NSColor(srgbRed: 0.60, green: 0.76, blue: 1.00, alpha: 0.24),
                dark: NSColor(srgbRed: 0.60, green: 0.72, blue: 0.82, alpha: 0.16)
            )
        }

        static var strongHairline: Color {
            adaptive(
                light: NSColor(srgbRed: 0.45, green: 0.68, blue: 1.00, alpha: 0.34),
                dark: NSColor(srgbRed: 0.68, green: 0.80, blue: 0.90, alpha: 0.22)
            )
        }
    }

    enum Motion {
        static let progressGauge = Animation.easeInOut(duration: 0.34)
        static let buttonHover = Animation.easeOut(duration: 0.16)
    }

    enum Status {
        static let warning = ColorToken.warning
        static let warningFill = ColorToken.warning.opacity(0.11)
        static let warningStroke = ColorToken.warning.opacity(0.22)
    }

    enum Shadow {
        struct Layer {
            let color: Color
            let radius: CGFloat
            let x: CGFloat
            let y: CGFloat
        }

        static func colored(
            _ color: Color,
            darkColor: Color? = nil,
            ambientOpacity: Double = 0.10,
            darkAmbientOpacity: Double? = nil,
            contactOpacity: Double = 0.16
        ) -> [Layer] {
            let darkColor = darkColor ?? color
            let darkAmbientOpacity = darkAmbientOpacity ?? ambientOpacity

            return [
                Layer(color: adaptive(light: color.opacity(ambientOpacity), dark: darkColor.opacity(darkAmbientOpacity)), radius: 26, x: 0, y: 15),
                Layer(color: adaptive(light: color.opacity(contactOpacity), dark: darkColor.opacity(contactOpacity * 0.72)), radius: 10, x: 0, y: 7),
                Layer(color: Surface.hairline.opacity(0.72), radius: 6, x: 0, y: -2)
            ]
        }

        static let mirror = colored(
            ColorToken.glassTint,
            darkColor: ColorToken.accent,
            ambientOpacity: 0.18,
            darkAmbientOpacity: 0.13,
            contactOpacity: 0.14
        )

        static let accent = colored(
            ColorToken.accent,
            darkColor: ColorToken.glassTint,
            ambientOpacity: 0.12,
            darkAmbientOpacity: 0.10,
            contactOpacity: 0.10
        )

        static let panel = colored(
            ColorToken.glassTint,
            darkColor: ColorToken.glassTint,
            ambientOpacity: 0.07,
            darkAmbientOpacity: 0.08,
            contactOpacity: 0.06
        )

        static let control = colored(
            ColorToken.glassTint,
            darkColor: ColorToken.accent,
            ambientOpacity: 0.055,
            darkAmbientOpacity: 0.06,
            contactOpacity: 0.05
        )

        static let chip = colored(
            ColorToken.glassTint,
            darkColor: ColorToken.glassTint,
            ambientOpacity: 0.08,
            darkAmbientOpacity: 0.07,
            contactOpacity: 0.05
        )

        static let none: [Layer] = []
    }

    private static func adaptive(light: NSColor, dark: NSColor) -> Color {
        Color(nsColor: NSColor(name: nil) { appearance in
            switch appearance.bestMatch(from: [.darkAqua, .aqua]) {
            case .darkAqua:
                return dark
            default:
                return light
            }
        })
    }

    private static func adaptive(light: Color, dark: Color) -> Color {
        Color(nsColor: NSColor(name: nil) { appearance in
            switch appearance.bestMatch(from: [.darkAqua, .aqua]) {
            case .darkAqua:
                return NSColor(dark)
            default:
                return NSColor(light)
            }
        })
    }
}

private struct PingLayeredShadow: ViewModifier {
    let layers: [PingDesign.Shadow.Layer]

    func body(content: Content) -> some View {
        layers.reduce(AnyView(content)) { view, layer in
            AnyView(
                view.shadow(
                    color: layer.color,
                    radius: layer.radius,
                    x: layer.x,
                    y: layer.y
                )
            )
        }
    }
}

extension View {
    func pingShadow(_ layers: [PingDesign.Shadow.Layer]) -> some View {
        modifier(PingLayeredShadow(layers: layers))
    }
}
