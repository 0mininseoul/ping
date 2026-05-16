import Combine
import Foundation

@MainActor
final class MirrorViewModel: ObservableObject {
    enum State: Equatable {
        case idle
        case recording
        case uploading
        case failed(String)
    }

    @Published var state: State = .idle
    @Published var countdown: Int = 2

    func reset() {
        state = .idle
        countdown = 2
    }
}
