import XCTest

final class PlaybackControlsContractTests: XCTestCase {
    func testPlaybackWindowShowsReplayAndCloseHintAfterFirstPlayEnds() throws {
        let source = try readProjectSource("Ping/UI/Playback/PlaybackWindow.swift")

        XCTAssertTrue(source.contains("PlaybackWindowContent("))
        XCTAssertTrue(source.contains("@State private var showsControlsHint = false"))
        XCTAssertTrue(source.contains("showsControlsHint = true"))
        XCTAssertTrue(source.contains("↵ 다시 재생 · Esc 닫기"))
    }

    private func readProjectSource(_ relativePath: String) throws -> String {
        let projectRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()

        return try String(
            contentsOf: projectRoot.appendingPathComponent(relativePath),
            encoding: .utf8
        )
    }
}
