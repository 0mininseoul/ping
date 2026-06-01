import SwiftUI

struct PartnerPicker: View {
    @ObservedObject var appState: AppState
    @Binding var selectedRoomIds: Set<String>
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
            GlassChip(chipLabel, isHover: isExpanded)
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder private var dropdown: some View {
        VStack(spacing: 4) {
            if activeRooms.count >= 2 {
                optionRow(
                    label: "🌐 모두에게",
                    selected: selectedRoomIds.intersection(activeRoomIds).count == activeRoomIds.count
                ) {
                    setAllRoomsSelected(selectedRoomIds.intersection(activeRoomIds).count != activeRoomIds.count)
                }
                Divider().opacity(0.3)
            }
            ForEach(Array(activeRooms.enumerated()), id: \.element.id) { index, room in
                optionRow(
                    label: "\(index + 1). \(partnerNickname(in: room))",
                    selected: isSelected(room)
                ) {
                    setRoom(room, selected: !isSelected(room))
                }
            }
        }
        .padding(8)
        .frame(width: 220)
        .background {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(PingDesign.Surface.panelFill.opacity(0.94))
                .pingGlassEffect()
                .overlay {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .strokeBorder(PingDesign.Surface.strongHairline.opacity(0.42), lineWidth: 0.8)
                }
        }
    }

    private func optionRow(label: String, selected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Image(systemName: selected ? "checkmark.square.fill" : "square")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(selected ? Color.white : Color.white.opacity(0.70))
                    .frame(width: 14)
                Text(label)
                    .font(PingFont.label)
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
                Spacer()
            }
            .padding(.horizontal, 6)
            .padding(.vertical, 4)
        }
        .buttonStyle(.plain)
    }

    private var activeRooms: [Room] {
        appState.rooms.filter { room in
            room.id != nil && room.memberUids.count >= RoomLimits.minSendableMembers
        }
    }

    private var activeRoomIds: Set<String> {
        Set(activeRooms.compactMap(\.id))
    }

    private var selectedRooms: [Room] {
        activeRooms.filter { room in
            guard let id = room.id else { return false }
            return selectedRoomIds.contains(id)
        }
    }

    private var chipLabel: String {
        let selected = selectedRooms
        guard !selected.isEmpty else { return "파트너 없음" }

        if selected.count == 1, let room = selected.first {
            return "👤 \(partnerNickname(in: room))"
        }

        if selected.count == activeRooms.count {
            return "🌐 모두에게 (\(selected.count))"
        }

        return "👥 \(selected.count)개 룸"
    }

    private func isSelected(_ room: Room) -> Bool {
        guard let id = room.id else { return false }
        return selectedRoomIds.contains(id)
    }

    private func setRoom(_ room: Room, selected: Bool) {
        guard let id = room.id else { return }

        if selected {
            selectedRoomIds.insert(id)
        } else {
            selectedRoomIds.remove(id)
        }

        updateSendMode()
    }

    private func setAllRoomsSelected(_ selected: Bool) {
        selectedRoomIds = selected ? activeRoomIds : []
        updateSendMode()
    }

    private func updateSendMode() {
        let selectedCount = selectedRoomIds.intersection(activeRoomIds).count

        if selectedCount >= 2 && selectedCount == activeRoomIds.count {
            appState.sendMode = .allPartners
        } else if selectedCount >= 2 {
            appState.sendMode = .selectedRooms
        } else {
            appState.sendMode = .singlePartner
        }
    }

    private func partnerNickname(in room: Room) -> String {
        guard let myUid = appState.currentUser?.id else { return "?" }
        return room.memberNicknames.first(where: { $0.key != myUid })?.value ?? "?"
    }
}
