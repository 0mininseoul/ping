import XCTest

final class PlaybackPrefetchContractTests: XCTestCase {
    func testIncomingNotificationDoesNotDownloadVideoBeforeClickPlayback() throws {
        let appDelegateSource = try readSourceFile("Ping/AppDelegate.swift")

        XCTAssertTrue(appDelegateSource.contains("playbackCache"))
        XCTAssertFalse(appDelegateSource.contains("playbackPrefetchTasks"))
        XCTAssertFalse(appDelegateSource.contains("prefetchMessageVideo(message)"))
        XCTAssertTrue(appDelegateSource.contains("cachedVideoURL(for: message)"))
    }

    private func readSourceFile(_ relativePath: String) throws -> String {
        let fileName = URL(fileURLWithPath: relativePath).lastPathComponent
        let fileURL = try XCTUnwrap(Bundle(for: Self.self).resourceURL?.appendingPathComponent(fileName))

        return try String(contentsOf: fileURL, encoding: .utf8)
    }
}
