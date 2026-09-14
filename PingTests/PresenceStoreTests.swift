import XCTest
@testable import Ping

@MainActor
final class PresenceStoreTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_757_800_000)

    func testRefreshPublishesPresencePerMember() async {
        let store = PresenceStore { _ in
            [
                DesktopPresenceRow(uid: "a", lastSeenAt: self.now, isLive: true),
                DesktopPresenceRow(uid: "b", lastSeenAt: self.now.addingTimeInterval(-600), isLive: false)
            ]
        }

        await store.refresh(roomIds: ["room-1"])

        XCTAssertEqual(store.members["a"]?.isLive, true)
        XCTAssertEqual(store.members["b"]?.isLive, false)
    }

    func testTheRequestedRoomsReachTheLoader() async {
        var requested: [String]?
        let store = PresenceStore { roomIds in
            requested = roomIds
            return []
        }

        await store.refresh(roomIds: ["room-1", "room-2"])

        XCTAssertEqual(requested, ["room-1", "room-2"])
    }

    /// 네트워크가 잠깐 끊겼다고 팝오버의 상태 점이 전부 회색으로 바뀌면 안 된다.
    /// 직전에 확인한 상태를 그대로 들고 있는 편이 낫다.
    func testAFailedRefreshKeepsTheLastKnownPresence() async {
        var shouldFail = false
        let store = PresenceStore { _ in
            if shouldFail { throw PresenceLoadFailure() }
            return [DesktopPresenceRow(uid: "a", lastSeenAt: self.now, isLive: true)]
        }

        await store.refresh(roomIds: ["room-1"])
        shouldFail = true
        await store.refresh(roomIds: ["room-1"])

        XCTAssertEqual(store.members["a"]?.isLive, true)
    }

    /// 방이 하나도 없으면 물어볼 것도 없다.
    func testNoRoomsSkipsTheRequest() async {
        var calls = 0
        let store = PresenceStore { _ in
            calls += 1
            return []
        }

        await store.refresh(roomIds: [])

        XCTAssertEqual(calls, 0)
        XCTAssertTrue(store.members.isEmpty)
    }
}

private struct PresenceLoadFailure: Error {}
