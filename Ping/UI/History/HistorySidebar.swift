import SwiftUI

struct HistorySidebar: View {
    let rooms: [Room]
    @Binding var selectedRoomId: String?

    var body: some View {
        List(rooms, id: \.id, selection: $selectedRoomId) { room in
            VStack(alignment: .leading, spacing: 4) {
                Text(room.name)
                    .font(.headline)
                    .lineLimit(1)
                Text("\(room.memberUids.count)명")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .tag(room.id)
        }
        .listStyle(.sidebar)
    }
}
