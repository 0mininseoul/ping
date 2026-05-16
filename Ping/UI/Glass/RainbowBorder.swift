import SwiftUI

struct RainbowBorder: View {
    @State private var rotation: Angle = .zero
    let lineWidth: CGFloat

    var body: some View {
        Circle()
            .strokeBorder(
                AngularGradient(
                    colors: [.red, .orange, .yellow, .green, .blue, .purple, .red],
                    center: .center,
                    angle: rotation
                ),
                lineWidth: lineWidth
            )
            .onAppear {
                withAnimation(.linear(duration: 4).repeatForever(autoreverses: false)) {
                    rotation = .degrees(360)
                }
            }
    }
}
