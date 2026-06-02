import SwiftUI

struct InvitationCard: View {
    let invitation: Invitation
    var onAccept: () -> Void
    var onReject: () -> Void

    var body: some View {
        GlassPanel {
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .top, spacing: 10) {
                    Image(systemName: "envelope.badge.fill")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(.secondary)

                    VStack(alignment: .leading, spacing: 4) {
                        Text("\(invitation.fromNickname)님의 초대")
                            .font(PingFont.body)
                            .lineLimit(1)
                        Text(invitation.roomName)
                            .font(PingFont.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                    }

                    Spacer(minLength: 4)
                }

                HStack(spacing: 8) {
                    GlassButton("거부") {
                        onReject()
                    }
                    Spacer()
                    GlassButton("수락", isPrimary: true) {
                        onAccept()
                    }
                }
            }
            .padding(12)
        }
    }
}
