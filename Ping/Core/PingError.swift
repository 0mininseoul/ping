import Foundation

enum PingError: LocalizedError {
    case supabaseConfigurationMissing
    case supabaseUnavailable
    case supabaseRequestFailed(statusCode: Int, message: String)
    case currentUserMissing
    case noRecipients
    case messageIdMissing
    case invalidStorageURL
    case invalidVideoPayload
    case videoPayloadTooLarge
    case roomUnavailable

    var errorDescription: String? {
        switch self {
        case .supabaseConfigurationMissing:
            return "Resources/Supabase.plist가 없어 Supabase를 시작할 수 없습니다."
        case .supabaseUnavailable:
            return "Supabase 클라이언트가 아직 준비되지 않았습니다."
        case let .supabaseRequestFailed(statusCode, message):
            return "Supabase 요청이 실패했습니다. (\(statusCode)) \(message)"
        case .currentUserMissing:
            return "현재 사용자 정보가 없습니다."
        case .noRecipients:
            return "전송할 파트너가 없습니다."
        case .messageIdMissing:
            return "메시지 ID가 없습니다."
        case .invalidStorageURL:
            return "영상 다운로드 URL이 올바르지 않습니다."
        case .invalidVideoPayload:
            return "전송할 영상 파일이 올바르지 않습니다."
        case .videoPayloadTooLarge:
            return "영상 파일이 너무 큽니다. 다시 짧게 녹화해 주세요."
        case .roomUnavailable:
            return "룸에 참여할 수 없습니다."
        }
    }
}
