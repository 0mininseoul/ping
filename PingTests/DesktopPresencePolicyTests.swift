import XCTest
@testable import Ping

final class DesktopPresencePolicyTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_757_800_000)

    // MARK: - Merging device rows

    func testASingleLiveDeviceMakesTheMemberLive() {
        let merged = DesktopPresencePolicy.merge([
            row(uid: "a", secondsAgo: 5, isLive: true)
        ])

        XCTAssertEqual(merged["a"]?.isLive, true)
        XCTAssertEqual(merged["a"]?.lastSeenAt, now.addingTimeInterval(-5))
    }

    /// 한 사람이 맥을 두 대 쓰면 행도 두 개다. 한 대라도 켜져 있으면 접속 중이다.
    func testAnyLiveDeviceMakesTheMemberLive() {
        let merged = DesktopPresencePolicy.merge([
            row(uid: "a", secondsAgo: 7200, isLive: false),
            row(uid: "a", secondsAgo: 5, isLive: true)
        ])

        XCTAssertEqual(merged["a"]?.isLive, true)
    }

    func testTheMostRecentDeviceWinsTheLastSeenTime() {
        let merged = DesktopPresencePolicy.merge([
            row(uid: "a", secondsAgo: 7200, isLive: false),
            row(uid: "a", secondsAgo: 600, isLive: false)
        ])

        XCTAssertEqual(merged["a"]?.isLive, false)
        XCTAssertEqual(merged["a"]?.lastSeenAt, now.addingTimeInterval(-600))
    }

    func testMembersAreKeptApart() {
        let merged = DesktopPresencePolicy.merge([
            row(uid: "a", secondsAgo: 5, isLive: true),
            row(uid: "b", secondsAgo: 7200, isLive: false)
        ])

        XCTAssertEqual(merged["a"]?.isLive, true)
        XCTAssertEqual(merged["b"]?.isLive, false)
    }

    /// 하트비트를 한 번도 보낸 적 없는 멤버는 행 자체가 없다.
    func testAMemberWithoutAnyRowIsAbsent() {
        let merged = DesktopPresencePolicy.merge([
            row(uid: "a", secondsAgo: 5, isLive: true)
        ])

        XCTAssertNil(merged["never-seen"])
    }

    // MARK: - Last seen wording

    func testJustNow() {
        XCTAssertEqual(lastSeenText(secondsAgo: 0), "방금 전")
        XCTAssertEqual(lastSeenText(secondsAgo: 59), "방금 전")
    }

    func testMinutes() {
        XCTAssertEqual(lastSeenText(secondsAgo: 60), "1분 전")
        XCTAssertEqual(lastSeenText(secondsAgo: 3599), "59분 전")
    }

    func testHours() {
        XCTAssertEqual(lastSeenText(secondsAgo: 3600), "1시간 전")
        XCTAssertEqual(lastSeenText(secondsAgo: 10800), "3시간 전")
        XCTAssertEqual(lastSeenText(secondsAgo: 86399), "23시간 전")
    }

    func testDays() {
        XCTAssertEqual(lastSeenText(secondsAgo: 86400), "1일 전")
        XCTAssertEqual(lastSeenText(secondsAgo: 86400 * 42), "42일 전")
    }

    /// 서버와 기기 시계가 어긋나면 마지막 접속이 미래로 보인다. "-3분 전"을 보여주면 안 된다.
    func testAFutureTimestampReadsAsJustNow() {
        XCTAssertEqual(lastSeenText(secondsAgo: -180), "방금 전")
    }

    // MARK: - Live member labels (menubar)

    func testOnlyLiveMembersAreListed() {
        let names = DesktopPresencePolicy.liveMemberNames(
            memberUids: ["a", "b"],
            excluding: nil,
            presence: [
                "a": MemberPresence(isLive: true, lastSeenAt: now),
                "b": MemberPresence(isLive: false, lastSeenAt: now)
            ],
            nicknameForUid: { ["a": "민수", "b": "영희"][$0] ?? "" }
        )

        XCTAssertEqual(names, ["민수"])
    }

    /// 메뉴바는 방 단위가 아니라 내 모든 방을 합쳐 보여준다. 두 방에 같이 있는
    /// 사람이 두 번 나오면 안 된다.
    func testAMemberSharedByTwoRoomsIsListedOnce() {
        let names = DesktopPresencePolicy.liveMemberNames(
            memberUids: ["a", "a", "b"],
            excluding: nil,
            presence: [
                "a": MemberPresence(isLive: true, lastSeenAt: now),
                "b": MemberPresence(isLive: true, lastSeenAt: now)
            ],
            nicknameForUid: { ["a": "민수", "b": "영희"][$0] ?? "" }
        )

        XCTAssertEqual(names, ["민수", "영희"])
    }

    func testMyOwnMacIsNotListed() {
        let names = DesktopPresencePolicy.liveMemberNames(
            memberUids: ["me", "a"],
            excluding: "me",
            presence: [
                "me": MemberPresence(isLive: true, lastSeenAt: now),
                "a": MemberPresence(isLive: true, lastSeenAt: now)
            ],
            nicknameForUid: { ["me": "나", "a": "민수"][$0] ?? "" }
        )

        XCTAssertEqual(names, ["민수"])
    }

    func testNamesAreSorted() {
        let names = DesktopPresencePolicy.liveMemberNames(
            memberUids: ["a", "b", "c"],
            excluding: nil,
            presence: [
                "a": MemberPresence(isLive: true, lastSeenAt: now),
                "b": MemberPresence(isLive: true, lastSeenAt: now),
                "c": MemberPresence(isLive: true, lastSeenAt: now)
            ],
            nicknameForUid: { ["a": "지훈", "b": "가영", "c": "민수"][$0] ?? "" }
        )

        XCTAssertEqual(names, ["가영", "민수", "지훈"])
    }

    /// 하트비트를 한 번도 보낸 적 없는 멤버는 상태 자체가 없다.
    func testMembersWithoutPresenceAreNotListed() {
        let names = DesktopPresencePolicy.liveMemberNames(
            memberUids: ["a"],
            excluding: nil,
            presence: [:],
            nicknameForUid: { _ in "민수" }
        )

        XCTAssertTrue(names.isEmpty)
    }

    // MARK: - Helpers

    private func row(uid: String, secondsAgo: TimeInterval, isLive: Bool) -> DesktopPresenceRow {
        DesktopPresenceRow(
            uid: uid,
            lastSeenAt: now.addingTimeInterval(-secondsAgo),
            isLive: isLive
        )
    }

    private func lastSeenText(secondsAgo: TimeInterval) -> String {
        DesktopPresencePolicy.lastSeenText(now.addingTimeInterval(-secondsAgo), now: now)
    }
}
