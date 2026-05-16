import Foundation

enum PingError: LocalizedError {
    case firebaseConfigurationMissing
    case firestoreUnavailable
    case currentUserMissing
    case noRecipients
    case messageIdMissing
    case invalidStorageURL

    var errorDescription: String? {
        switch self {
        case .firebaseConfigurationMissing:
            return "Resources/GoogleService-Info.plist가 없어 Firebase를 시작할 수 없습니다."
        case .firestoreUnavailable:
            return "Firestore가 아직 준비되지 않았습니다."
        case .currentUserMissing:
            return "현재 사용자 정보가 없습니다."
        case .noRecipients:
            return "전송할 파트너가 없습니다."
        case .messageIdMissing:
            return "메시지 ID가 없습니다."
        case .invalidStorageURL:
            return "영상 다운로드 URL이 올바르지 않습니다."
        }
    }
}
