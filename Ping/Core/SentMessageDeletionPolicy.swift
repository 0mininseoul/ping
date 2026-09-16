import Foundation

/// 보낸 사람이 "모두에게서 삭제"할 수 있는 시간.
///
/// 서버 `ping_remove_video_message`·`ping_delete_chat`이 같은 값으로 거절한다. 한쪽만 바꾸면
/// 누를 수 있는 메뉴가 "삭제 실패"만 남기거나, 구버전 앱이 오래된 메시지를 계속 지운다.
enum SentMessageDeletionPolicy {
    static let window: TimeInterval = 5 * 60
    static let expiredMessage = "보낸 지 5분이 지나 삭제할 수 없어요."

    static func canDelete(createdAt: Date?, now: Date) -> Bool {
        guard let createdAt else { return false }
        return now.timeIntervalSince(createdAt) <= window
    }

    static func isWindowExpired(_ error: Error) -> Bool {
        guard case let .supabaseRequestFailed(_, message)? = error as? PingError else { return false }
        return message.contains("delete_window_expired")
    }
}
