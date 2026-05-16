import SwiftUI

struct PartnerPicker: View {
    @ObservedObject var appState: AppState
    @Binding var selectedRoomId: String?
    @Binding var isExpanded: Bool

    var body: some View {
        VStack(spacing: 6) {
            if isExpanded {
                dropdown
                    .transition(.opacity.combined(with: .move(edge: .bottom)))
            }
            chip
        }
        .animation(.easeOut(duration: 0.15), value: isExpanded)
    }

    @ViewBuilder private var chip: some View {
        Button {
            isExpanded.toggle()
        } label: {
            switch appState.sendMode {
            case .singlePartner:
                if let room = currentRoom() {
                    GlassChip("👤 \(partnerNickname(in: room))", isHover: isExpanded)
                } else {
                    GlassChip("파트너 없음", isHover: isExpanded)
                }
            case .allPartners:
                GlassChip("🌐 모두에게 (\(appState.rooms.count))", isHover: isExpanded)
            }
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder private var dropdown: some View {
        VStack(spacing: 4) {
            optionRow(label: "🌐 모두에게", selected: appState.sendMode == .allPartners) {
                appState.sendMode = .allPartners
                isExpanded = false
            }
            Divider().opacity(0.3)
            ForEach(Array(appState.rooms.enumerated()), id: \.element.id) { index, room in
                optionRow(
                    label: "\(index + 1). \(partnerNickname(in: room))",
                    selected: appState.sendMode == .singlePartner && selectedRoomId == room.id
                ) {
                    selectedRoomId = room.id
                    appState.sendMode = .singlePartner
                    isExpanded = false
                }
            }
        }
        .padding(8)
        .frame(maxWidth: 180)
        .background {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .glassEffect()
        }
    }

    private func optionRow(label: String, selected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack {
                Text(label)
                    .font(PingFont.label)
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
                Spacer()
                if selected {
                    Image(systemName: "checkmark")
                        .font(.system(size: 10, weight: .semibold))
                }
            }
            .padding(.horizontal, 6)
            .padding(.vertical, 4)
        }
        .buttonStyle(.plain)
    }

    private func currentRoom() -> Room? {
        guard let selectedRoomId else { return appState.defaultRoom }
        return appState.rooms.first(where: { $0.id == selectedRoomId }) ?? appState.defaultRoom
    }

    private func partnerNickname(in room: Room) -> String {
        guard let myUid = appState.currentUser?.id else { return "?" }
        return room.memberNicknames.first(where: { $0.key != myUid })?.value ?? "?"
    }
}
