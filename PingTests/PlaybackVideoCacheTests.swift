import XCTest
@testable import Ping

@MainActor final class PlaybackVideoCacheTests: XCTestCase {
    private var tempRoot: URL!

    override func setUpWithError() throws {
        tempRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("PlaybackVideoCacheTests.\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempRoot, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: tempRoot)
    }

    // MARK: - Fixtures

    private func message(id: String? = "m1") -> VideoMessage {
        VideoMessage(
            id: id,
            roomId: "r1",
            senderUid: "sender",
            receiverUid: "receiver",
            senderNickname: "나롱",
            videoId: "v1",
            videoUrl: "sender/v1.mp4",
            durationMs: 3000,
            mirrorPosition: MirrorPosition(xRatio: 0.5, yRatio: 0.5),
            status: .uploaded,
            createdAt: Date(),
            expiresAt: Date().addingTimeInterval(3600)
        )
    }

    private func makeFile(named name: String) throws -> URL {
        let url = tempRoot.appendingPathComponent(name)
        try Data("video".utf8).write(to: url)
        return url
    }

    /// 데드락은 실패가 아니라 정지로 나타난다. task group으로 감싸면 그룹이 멈춘 자식을
    /// 끝까지 기다리므로 테스트가 실패하지 않고 통째로 멈춘다. 결과를 분리된 task에 맡기고
    /// 값만 폴링해야 제한 시간 안에 실패로 떨어진다.
    private func value<T: Sendable>(
        within seconds: Double = 2,
        of operation: @escaping @Sendable @MainActor () async -> T
    ) async throws -> T {
        let box = ResultBox<T>()
        let work = Task { @MainActor in await box.set(operation()) }
        defer { work.cancel() }

        let deadline = Date().addingTimeInterval(seconds)
        repeat {
            if let value = await box.take() { return value }
            try await Task.sleep(nanoseconds: 5_000_000)
        } while Date() < deadline

        XCTFail("작업이 \(seconds)초 안에 끝나지 않았습니다 (데드락 의심)")
        throw TimedOut()
    }

    private struct TimedOut: Error {}

    // MARK: - Tests

    /// 회귀 방지: 프리페치 task가 자기 자신을 await 하면 영구 정지하고,
    /// 수신 루프가 직렬이라 그 뒤 모든 영상 알림이 함께 죽는다.
    func testPrefetchCompletesInsteadOfAwaitingItself() async throws {
        let file = try makeFile(named: "m1.mp4")
        let cache = PlaybackVideoCache { _ in file }

        let url = try await value { await cache.prefetch(self.message()) }

        XCTAssertEqual(url, file)
    }

    func testURLResolvesWhileAPrefetchIsInFlight() async throws {
        let file = try makeFile(named: "m1.mp4")
        let gate = Gate()
        let cache = PlaybackVideoCache { _ in
            await gate.wait()
            return file
        }

        let prefetch = Task { @MainActor in await cache.prefetch(self.message()) }
        await Task.yield()
        let joined = Task { @MainActor in try await cache.url(for: self.message()) }
        await gate.open()

        let prefetched = try await value { await prefetch.value }
        let resolved = try await value { try? await joined.value }
        XCTAssertEqual(prefetched, file)
        XCTAssertEqual(resolved, file)
    }

    func testConcurrentRequestsDownloadOnlyOnce() async throws {
        let file = try makeFile(named: "m1.mp4")
        let counter = Counter()
        let gate = Gate()
        let cache = PlaybackVideoCache { _ in
            await counter.increment()
            await gate.wait()
            return file
        }

        let first = Task { @MainActor in await cache.prefetch(self.message()) }
        await Task.yield()
        let second = Task { @MainActor in await cache.prefetch(self.message()) }
        await Task.yield()
        await gate.open()

        _ = try await value { await first.value }
        _ = try await value { await second.value }
        let downloads = await counter.count
        XCTAssertEqual(downloads, 1)
    }

    func testCachedResultSkipsTheSecondDownload() async throws {
        let file = try makeFile(named: "m1.mp4")
        let counter = Counter()
        let cache = PlaybackVideoCache { _ in
            await counter.increment()
            return file
        }

        _ = try await value { await cache.prefetch(self.message()) }
        _ = try await value { await cache.prefetch(self.message()) }

        let downloads = await counter.count
        XCTAssertEqual(downloads, 1)
    }

    func testFailedDownloadReturnsNilAndAllowsRetry() async throws {
        let file = try makeFile(named: "m1.mp4")
        let counter = Counter()
        let cache = PlaybackVideoCache { _ in
            let attempt = await counter.incrementAndGet()
            if attempt == 1 { throw PingError.invalidStorageURL }
            return file
        }

        let failed = try await value { await cache.prefetch(self.message()) }
        XCTAssertNil(failed)

        let retried = try await value { await cache.prefetch(self.message()) }
        XCTAssertEqual(retried, file)
    }

    func testURLPropagatesDownloadFailure() async throws {
        let cache = PlaybackVideoCache { _ in throw PingError.invalidStorageURL }

        let result = try await value { () -> Bool in
            do {
                _ = try await cache.url(for: self.message())
                return false
            } catch {
                return true
            }
        }
        XCTAssertTrue(result, "다운로드 실패는 호출자에게 전달되어야 한다")
    }

    func testDiscardForcesAFreshDownload() async throws {
        let file = try makeFile(named: "m1.mp4")
        let counter = Counter()
        let cache = PlaybackVideoCache { _ in
            await counter.increment()
            return file
        }

        _ = try await value { await cache.prefetch(self.message()) }
        cache.discard(messageId: "m1")
        _ = try await value { await cache.prefetch(self.message()) }

        let downloads = await counter.count
        XCTAssertEqual(downloads, 2)
    }

    /// 캐시 파일이 사라지면(임시 폴더 정리 등) 항목을 신뢰하지 않는다.
    func testMissingFileIsNotServedFromCache() async throws {
        let file = try makeFile(named: "m1.mp4")
        let counter = Counter()
        let cache = PlaybackVideoCache { _ in
            await counter.increment()
            return file
        }

        _ = try await value { await cache.prefetch(self.message()) }
        try FileManager.default.removeItem(at: file)
        _ = try await value { await cache.prefetch(self.message()) }

        let downloads = await counter.count
        XCTAssertEqual(downloads, 2)
    }

    func testMessageWithoutIdStillResolves() async throws {
        let file = try makeFile(named: "anon.mp4")
        let cache = PlaybackVideoCache { _ in file }

        let url = try await value { await cache.prefetch(self.message(id: nil)) }

        XCTAssertEqual(url, file)
    }
}

// MARK: - Test helpers

private actor Gate {
    private var isOpen = false
    private var waiters: [CheckedContinuation<Void, Never>] = []

    func wait() async {
        if isOpen { return }
        await withCheckedContinuation { waiters.append($0) }
    }

    func open() {
        isOpen = true
        let pending = waiters
        waiters.removeAll()
        pending.forEach { $0.resume() }
    }
}

private actor ResultBox<T: Sendable> {
    private var value: T?

    func set(_ newValue: T) {
        value = newValue
    }

    func take() -> T? {
        value
    }
}

private actor Counter {
    private(set) var count = 0

    func increment() {
        count += 1
    }

    func incrementAndGet() -> Int {
        count += 1
        return count
    }
}
