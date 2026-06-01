import SwiftUI

enum PartnerPickerLayout {
    static let dropdownMaxWidth: CGFloat = 164
    static let dropdownMaxHeight: CGFloat = 104
}

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
            GlassChip(chipLabel, icon: chipIcon, isHover: isExpanded)
                .frame(maxWidth: PartnerPickerLayout.dropdownMaxWidth)
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder private var dropdown: some View {
        ScrollView(.vertical, showsIndicators: activeRooms.count >= 4) {
            VStack(spacing: 2) {
                if activeRooms.count >= 2 {
                    optionRow(
                        label: "모든 룸",
                        selected: selectedRoomIds.intersection(activeRoomIds).count == activeRoomIds.count
                    ) {
                        setAllRoomsSelected(selectedRoomIds.intersection(activeRoomIds).count != activeRoomIds.count)
                    }
                    Rectangle()
                        .fill(Color.white.opacity(0.16))
                        .frame(height: 1)
                        .padding(.vertical, 2)
                }
                ForEach(Array(activeRooms.enumerated()), id: \.element.id) { index, room in
                    optionRow(
                        label: "\(index + 1). \(roomLabel(in: room))",
                        selected: isSelected(room)
                    ) {
                        setRoom(room, selected: !isSelected(room))
                    }
                }
            }
            .padding(6)
        }
        .frame(width: PartnerPickerLayout.dropdownMaxWidth)
        .frame(maxHeight: PartnerPickerLayout.dropdownMaxHeight)
        .background {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color.black.opacity(0.68))
                .overlay {
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .strokeBorder(Color.white.opacity(0.16), lineWidth: 0.8)
                }
        }
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .shadow(color: Color.black.opacity(0.18), radius: 8, y: 4)
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
                    .minimumScaleFactor(0.72)
                Spacer()
            }
            .padding(.horizontal, 7)
            .padding(.vertical, 5)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(selected ? Color.white.opacity(0.12) : Color.clear)
            }
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
            return roomLabel(in: room)
        }

        if selected.count == activeRooms.count {
            return "모든 룸 (\(selected.count))"
        }

        return "👥 \(selected.count)개 룸"
    }

    private var chipIcon: String? {
        let selected = selectedRooms
        guard !selected.isEmpty else { return "person.crop.circle.badge.exclamationmark" }

        if selected.count == activeRooms.count, activeRooms.count >= 2 {
            return "globe"
        }

        return "person.2.fill"
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

    private func roomLabel(in room: Room) -> String {
        return room.name
    }
}
