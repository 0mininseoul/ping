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

/// 룸 창을 열 때 어떤 룸을 고를지. 알림 클릭이 지정한 룸이 언제나 최우선이다.
///
/// 알림을 클릭하면 AppDelegate가 `pendingRoomFocusId`를 세운 **뒤** 룸 창을 연다.
/// 창이 닫혀 있었으면 그 시점에 뷰가 새로 만들어지므로 SwiftUI `onChange`는 이미
/// 지나간 변경을 보지 못하고, 예전 초기 선택 로직은 `lastSelectedRoomId`만 봐서
/// 직전에 보던 룸이 열렸다(2026-09-14 확인). 두 경로가 같은 규칙을 타야 한다.
extension RoomFocusPolicy {
    struct InitialRoomSelection: Equatable {
        let roomId: String?
        /// 알림이 가리키는 룸을 실제로 선택했는가. 아직 룸 목록에 없어 선택하지
        /// 못했다면 false여야 한다 — 여기서 소비해버리면 목록이 도착한 뒤
        /// 적용할 기회가 사라진다.
        let consumesPendingFocus: Bool
    }

    static func initialRoomSelection(
        pendingRoomFocusId: String?,
        currentSelectionId: String?,
        lastSelectedRoomId: String?,
        availableRoomIds: [String],
        defaultRoomId: String?
    ) -> InitialRoomSelection {
        if let pendingRoomFocusId, availableRoomIds.contains(pendingRoomFocusId) {
            return InitialRoomSelection(roomId: pendingRoomFocusId, consumesPendingFocus: true)
        }

        if let currentSelectionId, availableRoomIds.contains(currentSelectionId) {
            return InitialRoomSelection(roomId: currentSelectionId, consumesPendingFocus: false)
        }

        if let lastSelectedRoomId, availableRoomIds.contains(lastSelectedRoomId) {
            return InitialRoomSelection(roomId: lastSelectedRoomId, consumesPendingFocus: false)
        }

        return InitialRoomSelection(
            roomId: defaultRoomId ?? availableRoomIds.first,
            consumesPendingFocus: false
        )
    }
}
