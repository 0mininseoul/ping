import Combine
import Foundation

/// 같은 방 멤버들의 데스크톱 상태를 들고 있는다. 팝오버나 메뉴를 열 때만 채우고,
/// 열려 있는 동안에만 갱신한다 — 평상시 네트워크를 쓰지 않기 위해서다.
@MainActor
final class PresenceStore: ObservableObject {
    typealias Loader = ([String]) async throws -> [DesktopPresenceRow]

    /// 멤버 팝오버와 메뉴바가 같은 스냅샷을 본다. 한쪽에서 갱신한 결과를
    /// 다른 쪽이 열릴 때 곧바로 쓸 수 있다.
    static let shared = PresenceStore()

    @Published private(set) var members: [String: MemberPresence] = [:]

    private let load: Loader

    init(load: @escaping Loader) {
        self.load = load
    }

    convenience init(service: DesktopPresenceService = DesktopPresenceService()) {
        self.init { roomIds in
            try await service.roomPresence(roomIds: roomIds)
        }
    }

    func refresh(roomIds: [String]) async {
        guard !roomIds.isEmpty else { return }

        do {
            members = DesktopPresencePolicy.merge(try await load(roomIds))
        } catch {
            // 잠깐의 실패로 점을 전부 회색으로 떨어뜨리면 "다 나갔다"로 읽힌다.
            // 직전에 확인한 상태를 그대로 둔다.
            NSLog("Room presence refresh failed: \(error)")
        }
    }

    func presence(for uid: String) -> MemberPresence? {
        members[uid]
    }
}
