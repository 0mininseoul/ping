import XCTest
@testable import Ping

final class AutoFaceReplyContractTests: XCTestCase {
    func testMigrationPersistsAndReturnsTheAutoReplyMarker() throws {
        let sql = try readFixture("20260910000100_auto_face_reply_on_ping.sql")

        XCTAssertTrue(sql.contains("add column if not exists is_auto_reply boolean not null default false"))
        XCTAssertTrue(sql.contains("is_auto_reply_value boolean default false"))

        // 표식을 읽어오지 못하면 수신 측이 루프를 멈출 수 없다.
        // 읽기 RPC 3개(incoming / get / room)가 전부 실어야 한다.
        XCTAssertEqual(sql.components(separatedBy: "m.is_auto_reply").count - 1, 3)
        for rpc in ["ping_incoming_messages", "ping_get_message", "ping_room_messages"] {
            XCTAssertTrue(sql.contains("create or replace function public.\(rpc)"), rpc)
        }
    }

    /// 구버전 클라이언트가 쓴 행과 마이그레이션 이전 행에는 컬럼이 없다. 없으면 "자동 회신 아님"이다.
    func testMessageDecodingTreatsAMissingMarkerAsANormalPing() throws {
        let json = """
        {
          "id": "m1",
          "room_id": "r1",
          "sender_uid": "u1",
          "receiver_uid": "u2",
          "sender_nickname": "수성",
          "video_id": "v1",
          "video_url": "u1/v1.mp4",
          "duration_ms": 3000,
          "mirror_position": {"xRatio": 0.5, "yRatio": 0.5},
          "status": "uploaded",
          "expires_at": 1000000
        }
        """.data(using: .utf8)!

        let message = try JSONDecoder().decode(VideoMessage.self, from: json)

        XCTAssertFalse(message.isAutoReply)
    }

    func testMessageDecodingCarriesTheAutoReplyMarker() throws {
        let json = """
        {
          "id": "m1",
          "room_id": "r1",
          "sender_uid": "u1",
          "receiver_uid": "u2",
          "sender_nickname": "수성",
          "video_id": "v1",
          "video_url": "u1/v1.mp4",
          "duration_ms": 3000,
          "mirror_position": {"xRatio": 0.5, "yRatio": 0.5},
          "status": "uploaded",
          "expires_at": 1000000,
          "is_auto_reply": true
        }
        """.data(using: .utf8)!

        let message = try JSONDecoder().decode(VideoMessage.self, from: json)

        XCTAssertTrue(message.isAutoReply)
    }

    /// 루프 차단 2차 방어. 자동 회신은 원 발신자 1명에게만 나가야 팬아웃이 불가능하다.
    func testAutoReplyIsAddressedOnlyToTheOriginalSender() throws {
        let source = try readFixture("MessageService.swift")

        XCTAssertTrue(source.contains("let receiverUid = originalMessage.senderUid"))
        XCTAssertTrue(source.contains("authorizedUids: [receiverUid]"))
        XCTAssertTrue(source.contains("\"is_auto_reply_value\": true"))
        XCTAssertTrue(source.contains("\"room_uuid\": originalMessage.roomId"))
    }

    /// APNs가 배너를 담당해도 실행 중 영상 observer의 자동 회신은 먼저 시작해야 한다.
    func testAutoReplyRunsBeforeTheVideoIsMarkedNotified() throws {
        let source = try readFixture("AppDelegate.swift")

        let delivery = try sourceSlice(
            in: source,
            from: "private func deliverIncomingVideo",
            to: "private func fetchIncomingVideosNow"
        )
        let hookIndex = try XCTUnwrap(delivery.range(of: "autoFaceReply.handleIncoming")?.lowerBound)
        let markIndex = try XCTUnwrap(delivery.range(of: "ledger.remember(.video")?.lowerBound)

        XCTAssertLessThan(hookIndex, markIndex)
        XCTAssertFalse(delivery.contains("notifyIncomingMessage"))
    }

    func testCoordinatorDelegatesTheDecisionToThePolicyWithoutAUserPreference() throws {
        let source = try readFixture("AutoFaceReplyCoordinator.swift")

        XCTAssertTrue(source.contains("AutoFaceReplyPolicy.decide"))
        XCTAssertTrue(source.contains("incomingIsAutoReply: message.isAutoReply"))
        XCTAssertFalse(source.contains("PingAutoFaceReplyPreference"))
        XCTAssertTrue(source.contains("auto_face_reply_skipped"))
    }

    /// 도착 순간의 결정만 믿으면 잠 때문에 멈췄던 녹화가 깨어난 뒤 몇 시간 늦게 나간다.
    /// 녹화 직전과 전송 직전에 다시 재야 한다.
    func testCoordinatorRechecksFreshnessBeforeRecordingAndBeforeSending() throws {
        let source = try readFixture("AutoFaceReplyCoordinator.swift")

        let startIndex = try XCTUnwrap(source.range(of: "camera.startWithAudio()")?.upperBound)
        let recordIndex = try XCTUnwrap(source.range(of: "recorder.recordClip")?.lowerBound)
        let sendIndex = try XCTUnwrap(source.range(of: "messageService.sendAutoReply")?.lowerBound)

        XCTAssertTrue(source[startIndex..<recordIndex].contains("guard !abandonIfNotLive(message)"))
        XCTAssertTrue(source[recordIndex..<sendIndex].contains("guard !abandonIfNotLive(message)"))
        XCTAssertTrue(source.contains("AutoFaceReplyPolicy.recheck("))
    }

    /// 다크웨이크에서는 앱이 핑을 받지만 카메라는 돌지 않는다. 디스플레이 상태를 정책에 넘기고,
    /// 녹화 도중 잠들면 카메라를 끊어 깨어난 순간 다시 켜지지 않게 한다.
    func testCoordinatorTracksDisplaySleepAndStopsAnInFlightReply() throws {
        let source = try readFixture("AutoFaceReplyCoordinator.swift")

        XCTAssertTrue(source.contains("isDisplayAsleep: Self.isDisplayAsleep"))
        XCTAssertTrue(source.contains("CGDisplayIsAsleep(CGMainDisplayID())"))
        XCTAssertTrue(source.contains("NSWorkspace.screensDidSleepNotification"))
        XCTAssertTrue(source.contains("NSWorkspace.willSleepNotification"))
        XCTAssertTrue(source.contains("movieOutput.stopRecording()"))
    }

    /// 원격 트리거로 웹캠이 켜지므로 본인이 알아챌 수 있어야 하고,
    /// 하던 일을 방해하면 안 되므로 포커스는 가져가지 않는다.
    func testIndicatorAnnouncesRecordingWithoutStealingFocusOrShowingAPreview() throws {
        let source = try readFixture("AutoReplyIndicatorWindow.swift")

        XCTAssertTrue(source.contains("자동 회신 녹화 중"))
        XCTAssertTrue(source.contains("override var canBecomeKey: Bool { false }"))
        XCTAssertTrue(source.contains("nonactivatingPanel"))
        XCTAssertTrue(source.contains("orderFrontRegardless()"))
        XCTAssertFalse(source.contains("CameraPreviewView"))
        XCTAssertFalse(source.contains("ForegroundPresenter"))
    }

    func testSettingsDoNotExposeAnAutoFaceReplyOptOut() throws {
        let source = try readFixture("SettingsScene.swift")

        XCTAssertFalse(source.contains("PingPreferenceKeys.autoFaceReplyOnPing"))
        XCTAssertFalse(source.contains("핑 받으면 자동으로 얼굴 회신"))
        XCTAssertFalse(source.contains("$autoFaceReplyOnPing"))
    }

    func testPreferencesDoNotRetainTheObsoleteAutoReplyKey() throws {
        let source = try readFixture("UserPreferences.swift")

        XCTAssertFalse(source.contains("autoFaceReplyOnPing"))
        XCTAssertFalse(source.contains("PingAutoFaceReplyPreference"))
    }

    private func readFixture(_ relativePath: String) throws -> String {
        let fileName = URL(fileURLWithPath: relativePath).lastPathComponent
        let fileURL = try XCTUnwrap(Bundle(for: Self.self).resourceURL?.appendingPathComponent(fileName))

        return try String(contentsOf: fileURL, encoding: .utf8)
    }

    private func sourceSlice(in source: String, from startMarker: String, to endMarker: String) throws -> String {
        let start = try XCTUnwrap(source.range(of: startMarker)?.lowerBound)
        let end = try XCTUnwrap(source.range(of: endMarker, range: start..<source.endIndex)?.lowerBound)
        return String(source[start..<end])
    }
}
