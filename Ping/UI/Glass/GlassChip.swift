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
        .foregroundStyle(.white)
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background {
            Capsule()
                .fill(Color.black.opacity(isHover ? 0.65 : 0.55))
                .pingGlassEffect()
        }
        .animation(.easeInOut(duration: 0.15), value: isHover)
    }
}
