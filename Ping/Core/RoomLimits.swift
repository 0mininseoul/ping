import Foundation

enum RoomLimits {
    static let maxRoomsPerUser = 8
    static let maxMembersPerRoom = 8
    static let minSendableMembers = 2
    static let maxRoomNameLength = 16

    static func sanitizedRoomName(_ value: String) -> String {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count > maxRoomNameLength else { return trimmed }
        return String(trimmed.prefix(maxRoomNameLength))
    }

    static func isValidRoomName(_ value: String) -> Bool {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return !trimmed.isEmpty && trimmed.count <= maxRoomNameLength
    }

    static func directRoomName(myNickname: String, otherNickname: String) -> String {
        sanitizedRoomName("\(myNickname) ↔ \(otherNickname)")
    }
}
