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

    /// 알림 권한이 없으면 notifyIncomingMessage가 조기 반환한다. 자동 회신이 그 뒤에 있으면
    /// 권한 없는 맥에서는 영영 동작하지 않는다.
    func testAutoReplyRunsBeforeTheNotificationPermissionEarlyReturn() throws {
        let source = try readFixture("AppDelegate.swift")

        let hookIndex = try XCTUnwrap(source.range(of: "autoFaceReply.handleIncoming")?.lowerBound)
        let guardIndex = try XCTUnwrap(source.range(of: "guard didScheduleNotification else")?.lowerBound)

        XCTAssertLessThan(hookIndex, guardIndex)
    }

    func testCoordinatorDelegatesTheDecisionToThePolicy() throws {
        let source = try readFixture("AutoFaceReplyCoordinator.swift")

        XCTAssertTrue(source.contains("AutoFaceReplyPolicy.decide"))
        XCTAssertTrue(source.contains("incomingIsAutoReply: message.isAutoReply"))
        XCTAssertTrue(source.contains("isEnabled: PingAutoFaceReplyPreference.isEnabled"))
        XCTAssertTrue(source.contains("auto_face_reply_skipped"))
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

    func testSettingsExposeAnOnOffCheckboxForAutoFaceReply() throws {
        let source = try readFixture("SettingsScene.swift")

        XCTAssertTrue(source.contains("@AppStorage(PingPreferenceKeys.autoFaceReplyOnPing)"))
        XCTAssertTrue(source.contains("핑 받으면 자동으로 얼굴 회신"))
        XCTAssertTrue(source.contains("Toggle(\"\", isOn: $autoFaceReplyOnPing)"))
    }

    private func readFixture(_ relativePath: String) throws -> String {
        let fileName = URL(fileURLWithPath: relativePath).lastPathComponent
        let fileURL = try XCTUnwrap(Bundle(for: Self.self).resourceURL?.appendingPathComponent(fileName))

        return try String(contentsOf: fileURL, encoding: .utf8)
    }
}
