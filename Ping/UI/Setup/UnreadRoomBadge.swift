import SwiftUI

struct UnreadRoomBadge: View {
    let count: Int

    var body: some View {
        Text(count > 99 ? "99+" : "\(count)")
            .font(.system(size: 11, weight: .bold))
            .foregroundStyle(.white)
            .monospacedDigit()
            .padding(.horizontal, 7)
            .padding(.vertical, 3)
            .background(Capsule().fill(Color.red))
            .accessibilityLabel("읽지 않은 메시지 \(count)개")
    }
}
