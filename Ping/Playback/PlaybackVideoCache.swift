import Foundation

/// 수신 영상의 로컬 파일 캐시와 진행 중인 다운로드를 관리한다.
///
/// 알림 경로와 자동 재생 경로가 같은 메시지를 동시에 요청할 수 있으므로 다운로드는
/// 메시지당 한 번만 수행하고, 나머지 호출자는 그 task에 합류한다.
///
/// 다운로드 task 본문은 오직 `download`만 호출한다. task 본문에서 다시 진행 중 task를
/// 조회하면 자기 자신을 await 하게 되어 영구 정지하고, 수신 루프가 직렬이라 그 뒤 모든
/// 영상 알림이 함께 죽는다. 이 분리를 되돌리지 말 것.
@MainActor
final class PlaybackVideoCache {
    typealias Downloader = @MainActor (VideoMessage) async throws -> URL

    private let download: Downloader
    private var cached: [String: URL] = [:]
    private var inFlight: [String: Task<URL, Error>] = [:]

    init(download: @escaping Downloader) {
        self.download = download
    }

    /// 재생 직전 호출. 캐시 → 진행 중 다운로드 합류 → 신규 다운로드 순으로 해결한다.
    func url(for message: VideoMessage) async throws -> URL {
        guard let id = message.id else {
            return try await download(message)
        }

        if let url = existingFile(for: id) {
            return url
        }

        let task = downloadTask(for: message, id: id)
        do {
            let url = try await task.value
            complete(id: id, task: task)
            cached[id] = url
            return url
        } catch {
            complete(id: id, task: task)
            throw error
        }
    }

    /// 알림과 자동 재생 전에 미리 받아 둔다. 실패는 nil로 흡수해 수신 루프를 막지 않는다.
    @discardableResult
    func prefetch(_ message: VideoMessage) async -> URL? {
        do {
            return try await url(for: message)
        } catch {
            NSLog("Video prefetch failed: \(error)")
            return nil
        }
    }

    func cachedURL(messageId: String) -> URL? {
        existingFile(for: messageId)
    }

    func discard(messageId: String) {
        cached[messageId] = nil
    }

    func cancelAll() {
        for task in inFlight.values {
            task.cancel()
        }
        inFlight.removeAll()
    }

    /// 계정 전환처럼 이전 사용자의 흔적을 남기면 안 되는 경우에 쓴다.
    func reset() {
        cancelAll()
        cached.removeAll()
    }

    private func downloadTask(for message: VideoMessage, id: String) -> Task<URL, Error> {
        if let existing = inFlight[id] {
            return existing
        }

        let download = self.download
        let task = Task { @MainActor () throws -> URL in
            try await download(message)
        }
        inFlight[id] = task
        return task
    }

    /// 합류한 호출자들이 순서대로 깨어나므로, 자기가 시작한 task만 걷어낸다.
    private func complete(id: String, task: Task<URL, Error>) {
        if inFlight[id] == task {
            inFlight[id] = nil
        }
    }

    private func existingFile(for id: String) -> URL? {
        guard let url = cached[id], FileManager.default.fileExists(atPath: url.path) else {
            return nil
        }
        return url
    }
}
