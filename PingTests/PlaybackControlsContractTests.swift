import XCTest

final class PlaybackControlsContractTests: XCTestCase {
    func testPlaybackWindowShowsReplayAndCloseHintAfterFirstPlayEnds() throws {
        let source = try readProjectSource("Ping/UI/Playback/PlaybackWindow.swift")

        XCTAssertTrue(source.contains("PlaybackWindowContent("))
        XCTAssertTrue(source.contains("@State private var showsControlsHint = false"))
        XCTAssertTrue(source.contains("showsControlsHint = true"))
        XCTAssertTrue(source.contains("↵ 다시 재생 · 클릭 또는 Esc 닫기"))
    }

    /// 자동 재생 창은 사용자가 부르지 않았으므로 마우스만으로도 지울 수 있어야 한다.
    func testPlaybackWindowCanBeDismissedByClicking() throws {
        let source = try readProjectSource("Ping/UI/Playback/PlaybackWindow.swift")

        XCTAssertTrue(source.contains("ignoresMouseEvents = false"))
        XCTAssertTrue(source.contains(".onTapGesture { onDismiss() }"))
        XCTAssertTrue(source.contains(".onHover { isHovering = $0 }"))
        XCTAssertTrue(source.contains("PlaybackDismissBadge"))
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
