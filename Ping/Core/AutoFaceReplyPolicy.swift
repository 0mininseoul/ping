import Foundation

/// 실시간으로 받은 핑에 자동으로 얼굴을 녹화해 되돌려 보낼지 결정한다.
///
/// 스킵 사유를 값으로 돌려주는 이유: "자동 회신이 안 왔다"는 신고를 추론이 아니라 조회로
/// 답하기 위해서다. 0.3.65~0.3.71 알림 장애 때 신호만 보고 판단했다가 여섯 번 틀렸다.
enum AutoFaceReplyPolicy {
    /// 이 창을 넘긴 핑은 자동 회신하지 않는다. 앱이 잠들기 전부터 떠 있었다면
    /// `createdAt > appStartedAt`은 자다 깬 뒤에도 참이라, 절대 시간 창이 없으면
    /// 어제 온 핑에 오늘 얼굴이 찍혀 나간다.
    static let freshnessWindow: TimeInterval = 60

    enum Skip: String, Equatable {
        case disabled
        case autoReplyMessage
        case alreadyReplied
        case missingTimestamp
        case staleMessage
        case cameraUnavailable
        case cameraBusy
    }

    enum Decision: Equatable {
        case record
        case skip(Skip)
    }

    struct Context {
        var isEnabled: Bool
        var incomingIsAutoReply: Bool
        var messageCreatedAt: Date?
        var appStartedAt: Date
        var now: Date
        var alreadyReplied: Bool
        var isCameraAuthorized: Bool
        var isCameraBusy: Bool
    }

    static func decide(_ context: Context) -> Decision {
        guard context.isEnabled else { return .skip(.disabled) }
        // 루프 차단 1차. 전송 대상을 원 발신자 1명으로 고정한 것이 2차 방어다.
        guard !context.incomingIsAutoReply else { return .skip(.autoReplyMessage) }
        guard !context.alreadyReplied else { return .skip(.alreadyReplied) }
        guard let createdAt = context.messageCreatedAt else { return .skip(.missingTimestamp) }
        guard createdAt > context.appStartedAt,
              context.now.timeIntervalSince(createdAt) <= freshnessWindow else {
            return .skip(.staleMessage)
        }
        guard context.isCameraAuthorized else { return .skip(.cameraUnavailable) }
        guard !context.isCameraBusy else { return .skip(.cameraBusy) }
        return .record
    }
}
