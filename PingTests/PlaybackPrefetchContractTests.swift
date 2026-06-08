import XCTest

final class PlaybackPrefetchContractTests: XCTestCase {
    func testIncomingNotificationDoesNotDownloadVideoBeforeClickPlayback() throws {
        let appDelegateSource = try readSourceFile("Ping/AppDelegate.swift")

        XCTAssertTrue(appDelegateSource.contains("playbackCache"))
        XCTAssertFalse(appDelegateSource.contains("playbackPrefetchTasks"))
        XCTAssertFalse(appDelegateSource.contains("prefetchMessageVideo(message)"))
        XCTAssertTrue(appDelegateSource.contains("cachedVideoURL(for: message)"))
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

    private func readRepositoryFile(_ relativePath: String) throws -> String {
        let testFile = URL(fileURLWithPath: #filePath)
        let repoRoot = testFile.deletingLastPathComponent().deletingLastPathComponent()
        let fileURL = repoRoot.appendingPathComponent(relativePath)

        return try String(contentsOf: fileURL, encoding: .utf8)
    }
}
