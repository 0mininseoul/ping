import Foundation

/// "지금 그 룸을 보고 있는가"를 판단한다. 보고 있는 룸의 채팅은 알림을 띄우지 않고,
/// 모바일 푸시도 억제한다.
///
/// 창이 떠 있다는 사실만으로 판단하면 안 된다. `NSWindow.isVisible`은 창이 다른 앱에
/// **완전히 가려져 있어도** true다. 그래서 룸 창을 열어둔 채 다른 일을 하는 동안 도착한
/// 채팅은 알림이 조용히 사라졌다(2026-09-03 확인). 영상 핑은 이 판단을 타지 않아
/// 정상적으로 떴고, 그래서 "영상은 뜨는데 텍스트는 안 뜬다"로 보였다.
///
/// 앱이 활성 상태인지까지 봐야 "보고 있다"에 가까워진다.
enum RoomFocusPolicy {
    static func isViewingRoom(
        roomId: String,
        appIsActive: Bool,
        roomWindowIsVisible: Bool,
        pendingRoomFocusId: String?,
        lastSelectedRoomId: String?
    ) -> Bool {
        guard appIsActive, roomWindowIsVisible else { return false }
        return pendingRoomFocusId == roomId || lastSelectedRoomId == roomId
    }

    /// 모바일 푸시 억제에 쓰는 활성 룸. 보고 있지 않으면 nil이어야 한다 —
    /// 그러지 않으면 데스크톱과 휴대폰 양쪽에서 알림이 사라진다.
    static func activeRoomIdForPresence(
        appIsActive: Bool,
        roomWindowIsVisible: Bool,
        lastSelectedRoomId: String?
    ) -> String? {
        guard appIsActive, roomWindowIsVisible else { return nil }
        return lastSelectedRoomId
    }
}
