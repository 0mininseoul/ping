import Combine
import Foundation

@MainActor
final class AppState: ObservableObject {
    static let shared = AppState()

    @Published var currentUser: PingUser?
    @Published var rooms: [Room] = []
    @Published var pendingInvitations: [Invitation] = []
    @Published var sendMode: SendMode = .singlePartner
    @Published var backendStatusMessage: String?
    @Published var pendingRoomFocusId: String?
    @Published var lastSelectedRoomId: String?

    init() {}

    enum SendMode: Equatable {
        case singlePartner
        case allPartners
    }

    var defaultRoom: Room? {
        let usableRooms = rooms.filter { $0.memberUids.count >= RoomLimits.minSendableMembers }
        let candidates = usableRooms.isEmpty ? rooms : usableRooms
        guard let lastId = currentUser?.lastUsedRoomId else { return candidates.first }
        return candidates.first(where: { $0.id == lastId }) ?? candidates.first
    }

    func cycleToNextPartner(currentRoomId: String?) -> Room? {
        let candidates = rooms.filter { $0.memberUids.count >= RoomLimits.minSendableMembers }
        guard !candidates.isEmpty else { return nil }
        guard let currentRoomId,
              let index = candidates.firstIndex(where: { $0.id == currentRoomId }) else {
            return candidates.first
        }
        return candidates[(index + 1) % candidates.count]
    }

    func selectPartner(at index: Int) -> Room? {
        let candidates = rooms.filter { $0.memberUids.count >= RoomLimits.minSendableMembers }
        guard index >= 1, index <= candidates.count else { return nil }
        return candidates[index - 1]
    }

    func resetTransientState() {
        sendMode = .singlePartner
        pendingInvitations = []
    }
}
