import XCTest
@testable import Ping

final class AutoFaceReplyPolicyTests: XCTestCase {
    private let launch = Date(timeIntervalSince1970: 1_000_000)

    private func context(
        incomingIsAutoReply: Bool = false,
        createdAtOffset: TimeInterval? = 5,
        nowOffset: TimeInterval = 10,
        alreadyReplied: Bool = false,
        isDisplayAsleep: Bool = false,
        isCameraAuthorized: Bool = true,
        isCameraBusy: Bool = false
    ) -> AutoFaceReplyPolicy.Context {
        AutoFaceReplyPolicy.Context(
            incomingIsAutoReply: incomingIsAutoReply,
            messageCreatedAt: createdAtOffset.map { launch.addingTimeInterval($0) },
            appStartedAt: launch,
            now: launch.addingTimeInterval(nowOffset),
            alreadyReplied: alreadyReplied,
            isDisplayAsleep: isDisplayAsleep,
            isCameraAuthorized: isCameraAuthorized,
            isCameraBusy: isCameraBusy
        )
    }

    func testRecordsForAFreshPingWhileEverythingIsReady() {
        XCTAssertEqual(AutoFaceReplyPolicy.decide(context()), .record)
    }

    /// 루프 차단의 1차 방어. 자동으로 녹화돼 온 핑에는 절대 다시 녹화하지 않는다.
    func testNeverRepliesToAnAutoReply() {
        XCTAssertEqual(
            AutoFaceReplyPolicy.decide(context(incomingIsAutoReply: true)),
            .skip(.autoReplyMessage)
        )
    }

    func testAutoReplyBlockBeatsAnOtherwisePerfectContext() {
        let decision = AutoFaceReplyPolicy.decide(
            context(incomingIsAutoReply: true, createdAtOffset: 1, nowOffset: 2)
        )
        XCTAssertEqual(decision, .skip(.autoReplyMessage))
    }

    func testSkipsMessagesWithoutATimestamp() {
        XCTAssertEqual(
            AutoFaceReplyPolicy.decide(context(createdAtOffset: nil)),
            .skip(.missingTimestamp)
        )
    }

    func testSkipsBacklogCreatedBeforeTheAppStarted() {
        XCTAssertEqual(
            AutoFaceReplyPolicy.decide(context(createdAtOffset: -30)),
            .skip(.staleMessage)
        )
    }

    /// "맥이 켜져 있지 않으면 생략"의 핵심 케이스. 앱은 자기 전부터 떠 있었으므로
    /// `createdAt > appStartedAt`은 여전히 참이다. 절대 시간 창이 없으면 자다 깬 뒤
    /// 폴링으로 들어온 어제 핑에 오늘 얼굴이 찍혀 나간다.
    func testSkipsAPingThatArrivedWhileTheMacWasAsleep() {
        let decision = AutoFaceReplyPolicy.decide(
            context(createdAtOffset: 3600, nowOffset: 7200)
        )
        XCTAssertEqual(decision, .skip(.staleMessage))
    }

    func testFreshnessWindowBoundaryIsInclusive() {
        let atLimit = context(
            createdAtOffset: 1,
            nowOffset: 1 + AutoFaceReplyPolicy.freshnessWindow
        )
        XCTAssertEqual(AutoFaceReplyPolicy.decide(atLimit), .record)

        let pastLimit = context(
            createdAtOffset: 1,
            nowOffset: 2 + AutoFaceReplyPolicy.freshnessWindow
        )
        XCTAssertEqual(AutoFaceReplyPolicy.decide(pastLimit), .skip(.staleMessage))
    }

    func testSkipsAMessageThisSessionAlreadyRepliedTo() {
        XCTAssertEqual(
            AutoFaceReplyPolicy.decide(context(alreadyReplied: true)),
            .skip(.alreadyReplied)
        )
    }

    func testSkipsWithoutCameraPermission() {
        XCTAssertEqual(
            AutoFaceReplyPolicy.decide(context(isCameraAuthorized: false)),
            .skip(.cameraUnavailable)
        )
    }

    /// 미러 창이 카메라를 쓰는 중에 세션을 가로채면 사용자가 직접 찍던 핑이 깨진다.
    func testSkipsWhileTheMirrorIsUsingTheCamera() {
        XCTAssertEqual(
            AutoFaceReplyPolicy.decide(context(isCameraBusy: true)),
            .skip(.cameraBusy)
        )
    }

    /// 0.3.76 사고. 디스플레이가 꺼진 다크웨이크에서도 네트워크는 살아 있어 핑이 실시간으로
    /// 도착한다. 그때 녹화를 걸면 카메라가 멈춘 채 기다리다 3시간 24분 뒤 깨운 순간 찍혀 나갔다.
    func testSkipsAFreshPingWhileTheDisplayIsAsleep() {
        XCTAssertEqual(
            AutoFaceReplyPolicy.decide(context(isDisplayAsleep: true)),
            .skip(.displayAsleep)
        )
    }

    func testRecheckLetsAFreshUninterruptedReplyThrough() {
        XCTAssertNil(
            AutoFaceReplyPolicy.recheck(
                messageCreatedAt: launch.addingTimeInterval(5),
                now: launch.addingTimeInterval(12),
                interruptedBySleep: false
            )
        )
    }

    /// 결정은 도착 순간 신선했어도 녹화가 잠 때문에 멈췄다 끝났으면 이미 실시간이 아니다.
    func testRecheckDropsAReplyThatFinishedAfterTheFreshnessWindow() {
        let createdAt = launch.addingTimeInterval(5)
        XCTAssertEqual(
            AutoFaceReplyPolicy.recheck(
                messageCreatedAt: createdAt,
                now: createdAt.addingTimeInterval(3 * 3600 + 24 * 60),
                interruptedBySleep: false
            ),
            .staleInFlight
        )
    }

    func testRecheckDropsAReplyWithoutATimestamp() {
        XCTAssertEqual(
            AutoFaceReplyPolicy.recheck(
                messageCreatedAt: nil,
                now: launch,
                interruptedBySleep: false
            ),
            .staleInFlight
        )
    }

    /// 잠들기 직전에 몇 초 안에 끝나 시간 창 안이더라도, 잘린 녹화는 보내지 않는다.
    func testRecheckDropsAReplyInterruptedBySleepEvenIfStillFresh() {
        XCTAssertEqual(
            AutoFaceReplyPolicy.recheck(
                messageCreatedAt: launch.addingTimeInterval(5),
                now: launch.addingTimeInterval(8),
                interruptedBySleep: true
            ),
            .interruptedBySleep
        )
    }

}
