import SwiftUI

struct GlassChip: View {
    let label: String
    let icon: String?
    let isHover: Bool

    init(_ label: String, icon: String? = nil, isHover: Bool = false) {
        self.label = label
        self.icon = icon
        self.isHover = isHover
    }

    var body: some View {
        HStack(spacing: 6) {
            if let icon {
                Image(systemName: icon)
                    .font(.system(size: 11, weight: .medium))
            }
            Text(label)
                .font(PingFont.label)
                .lineLimit(1)
                .minimumScaleFactor(0.75)
            Image(systemName: "chevron.down")
                .font(.system(size: 9, weight: .semibold))
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background {
            Capsule()
                .fill(PingDesign.Surface.rowFill.opacity(isHover ? 0.95 : 0.78))
                .glassEffect()
                .overlay {
                    Capsule()
                        .strokeBorder(
                            PingDesign.Surface.strongHairline.opacity(isHover ? 0.86 : 0.56),
                            lineWidth: 0.8
                        )
                }
        }
        .animation(.easeInOut(duration: 0.15), value: isHover)
    }
}
