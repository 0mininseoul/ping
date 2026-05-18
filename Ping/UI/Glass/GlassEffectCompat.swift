import SwiftUI

private struct PingTahoeGlassEffectModifier: ViewModifier {
    @ViewBuilder
    func body(content: Content) -> some View {
        if #available(macOS 26.0, *) {
            // macOS 26 Tahoe: use native Liquid Glass.
            content.glassEffect()
        } else {
            // pre-Tahoe fallback: callers provide stable tint fills and hairline overlays.
            content
        }
    }
}

extension View {
    func pingGlassEffect() -> some View {
        modifier(PingTahoeGlassEffectModifier())
    }
}
