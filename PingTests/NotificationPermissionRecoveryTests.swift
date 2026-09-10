import UserNotifications
import XCTest
@testable import Ping

final class NotificationPermissionRecoveryTests: XCTestCase {
    /// 온보딩을 건너뛴 기존 유저는 권한을 물어본 적이 없다. 이 상태에서는 macOS가
    /// 알림 레지스트리에 앱을 등록조차 하지 않아 시스템 설정 › 알림 목록에서
    /// 앱이 통째로 사라진다 — 사용자가 스스로 되돌릴 방법이 없는 유일한 상태다.
    func testRequestsOnceWhenPermissionWasNeverAsked() {
        XCTAssertTrue(NotificationPermissionRecovery.shouldRequestAuthorization(for: .notDetermined))
    }

    func testDoesNotReAskAfterTheUserAlreadyDecided() {
        XCTAssertFalse(NotificationPermissionRecovery.shouldRequestAuthorization(for: .authorized))
        XCTAssertFalse(NotificationPermissionRecovery.shouldRequestAuthorization(for: .denied))
        XCTAssertFalse(NotificationPermissionRecovery.shouldRequestAuthorization(for: .provisional))
    }

    /// 거부한 앱은 시스템 설정에 행이 남아 있으므로 그리로 보내면 되지만,
    /// 물어본 적 없는 앱은 행 자체가 없어서 앱이 직접 요청해야 한다.
    func testNeverAskedOffersAnInAppEnableButton() {
        XCTAssertEqual(NotificationPermissionRecovery.action(for: .notDetermined), .request)
    }

    func testDeniedSendsTheUserToSystemSettings() {
        XCTAssertEqual(NotificationPermissionRecovery.action(for: .denied), .openSettings)
    }

    func testAuthorizedNeedsNoAction() {
        XCTAssertEqual(NotificationPermissionRecovery.action(for: .authorized), .satisfied)
        XCTAssertEqual(NotificationPermissionRecovery.action(for: .provisional), .satisfied)
    }

    func testStatusDescriptionsTellTheUserWhichStateTheyAreIn() {
        XCTAssertEqual(NotificationPermissionRecovery.statusText(for: .authorized), "허용됨")
        XCTAssertEqual(NotificationPermissionRecovery.statusText(for: .notDetermined), "아직 요청하지 않음")
        XCTAssertEqual(NotificationPermissionRecovery.statusText(for: .denied), "거부됨")
    }
}
