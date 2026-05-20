import Combine
import Foundation

@MainActor
final class MirrorViewModel: ObservableObject {
    enum State: Equatable {
        case idle
        case recording
        case reviewing(URL)
        case uploading
        case failed(String)
    }

    @Published var state: State = .idle
    @Published var countdown: Int = 3

    func enterReviewing(url: URL) {
        state = .reviewing(url)
    }

    func beginUpload() {
        state = .uploading
    }

    func redo() {
        state = .recording
        countdown = 3
    }

    func reset() {
        state = .idle
        countdown = 3
    }
}
