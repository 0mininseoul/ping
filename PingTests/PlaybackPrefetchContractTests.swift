import XCTest

final class PlaybackPrefetchContractTests: XCTestCase {
    func testIncomingNotificationPrefetchesVideoIntoStableCache() throws {
        let appDelegateSource = try readSourceFile("Ping/AppDelegate.swift")

        XCTAssertTrue(appDelegateSource.contains("playbackVideoCache"))
        XCTAssertTrue(appDelegateSource.contains("await self.playbackVideoCache.prefetch(message)"))
        XCTAssertTrue(appDelegateSource.contains("playbackVideoCache.url(for: message)"))
    }

    /// 회귀 방지: 다운로드를 수신 루프 안에서 기다리면 느린 한 건이 뒤따르는 모든
    /// 알림을 막는다. 알림을 먼저 보내고 재생 준비는 별도 task로 넘겨야 한다.
    func testNotificationIsPostedBeforeTheVideoDownloadIsAwaited() throws {
        let appDelegateSource = try readSourceFile("Ping/AppDelegate.swift")

        let notificationRange = try XCTUnwrap(
            appDelegateSource.range(of: "LocalNotificationCenter.shared.notifyIncomingMessage")
        )
        let prefetchRange = try XCTUnwrap(
            appDelegateSource.range(of: "await self.playbackVideoCache.prefetch(message)")
        )
        XCTAssertLessThan(notificationRange.lowerBound, prefetchRange.lowerBound)
    }

    /// 회귀 방지: 프리페치 task 본문이 다시 진행 중 task를 조회하면 자기 자신을
    /// await 하게 되어 영구 정지한다. 다운로드 경로는 캐시 조회와 분리돼 있어야 한다.
    func testPrefetchTaskBodyDoesNotReenterTheCacheLookup() throws {
        let cacheSource = try readRepositoryFile("Ping/Playback/PlaybackVideoCache.swift")

        let taskBody = try sourceSlice(
            in: cacheSource,
            from: "private func downloadTask(",
            to: "private func complete("
        )
        XCTAssertTrue(taskBody.contains("try await download(message)"))
        XCTAssertFalse(taskBody.contains("url(for:"))
        XCTAssertFalse(taskBody.contains("prefetch("))
    }

    func testStorageServiceUsesStableCacheForRemoteVideoDownloads() throws {
        let storageSource = try readRepositoryFile("Ping/Backend/StorageService.swift")

        XCTAssertTrue(storageSource.contains("cachedDownloadURL(remotePath: remotePath)"))
        XCTAssertTrue(storageSource.contains("FileManager.default.fileExists(atPath: cachedURL.path)"))
        XCTAssertFalse(storageSource.contains("ping-dl-\\(UUID().uuidString)"))
    }

    func testMessageSendKeepsThirtyDayServerRetention() throws {
        let messageServiceSource = try readSourceFile("Ping/Backend/MessageService.swift")

        XCTAssertTrue(messageServiceSource.contains("30 * 24 * 60 * 60"))
        XCTAssertFalse(messageServiceSource.contains("Date().addingTimeInterval(24 * 60 * 60)"))
    }

    private func readSourceFile(_ relativePath: String) throws -> String {
        let fileName = URL(fileURLWithPath: relativePath).lastPathComponent
        let fileURL = try XCTUnwrap(Bundle(for: Self.self).resourceURL?.appendingPathComponent(fileName))

        return try String(contentsOf: fileURL, encoding: .utf8)
    }

    private func sourceSlice(in source: String, from startMarker: String, to endMarker: String) throws -> String {
        let start = try XCTUnwrap(source.range(of: startMarker)?.lowerBound)
        let end = try XCTUnwrap(source.range(of: endMarker, range: start..<source.endIndex)?.lowerBound)
        return String(source[start..<end])
    }

    private func readRepositoryFile(_ relativePath: String) throws -> String {
        let testFile = URL(fileURLWithPath: #filePath)
        let repoRoot = testFile.deletingLastPathComponent().deletingLastPathComponent()
        let fileURL = repoRoot.appendingPathComponent(relativePath)

        return try String(contentsOf: fileURL, encoding: .utf8)
    }
}
