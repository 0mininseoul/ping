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
    @Published var countdown: Int = 3

    func reset() {
        state = .idle
        countdown = 3
    }
}
