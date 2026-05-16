import SwiftUI

struct GlassButton: View {
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
                .foregroundStyle(isPrimary ? Color.white : Color.primary)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                .background {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .glassEffect()
                        .overlay {
                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .strokeBorder(Color.white.opacity(isPrimary ? 0.50 : 0.30), lineWidth: 1)
                        }
                        .background(
                            isPrimary ? Color.accentColor.opacity(0.60) : Color.clear,
                            in: RoundedRectangle(cornerRadius: 10, style: .continuous)
                        )
                }
        }
        .buttonStyle(.plain)
    }
}
