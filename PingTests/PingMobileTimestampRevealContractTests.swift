import XCTest

final class PingMobileTimestampRevealContractTests: XCTestCase {
    func testThreadViewUsesSharedHorizontalTimestampRevealOffset() throws {
        let source = try readProjectSource("PingMobile/ThreadView.swift")

        XCTAssertTrue(source.contains("@State private var timestampRevealOffset: CGFloat = 0"))
        XCTAssertTrue(source.contains("private let timestampWidth: CGFloat = 64"))
        XCTAssertTrue(source.contains("private let timestampGap: CGFloat = 12"))
        XCTAssertTrue(source.contains("private var timestampRevealMax: CGFloat"))
        XCTAssertTrue(source.contains("private let timestampResetAnimation: Animation"))
    }

    func testThreadViewRevealsTimestampsBehindRows() throws {
        let source = try readProjectSource("PingMobile/ThreadView.swift")
        let row = try extract(
            "private func timestampRevealRow",
            through: "private func timestampLabel",
            from: source
        )

        XCTAssertTrue(row.contains("ZStack(alignment: .trailing)"))
        XCTAssertTrue(row.contains("timestampLabel(for: item)"))
        XCTAssertTrue(row.contains("row(item)"))
        XCTAssertTrue(row.contains(".offset(x: timestampRevealOffset)"))
    }

    func testThreadViewGestureOnlyRespondsToHorizontalLeftDrag() throws {
        let source = try readProjectSource("PingMobile/ThreadView.swift")
        let gesture = try extract(
            "private var timestampRevealGesture",
            through: "private func updateTimestampRevealOffset",
            from: source
        )

        XCTAssertTrue(gesture.contains("DragGesture(minimumDistance: 10)"))
        XCTAssertTrue(gesture.contains("abs(value.translation.width) > abs(value.translation.height)"))
        XCTAssertTrue(gesture.contains("value.translation.width < 0"))
        XCTAssertTrue(gesture.contains("resetTimestampRevealOffset()"))
    }

    func testThreadViewWiresTimestampRevealIntoVisibleRowsAndScrollGesture() throws {
        let source = try readProjectSource("PingMobile/ThreadView.swift")

        XCTAssertTrue(source.contains("timestampRevealRow(for: item).id(item.id)"))
        XCTAssertTrue(source.contains(".simultaneousGesture(timestampRevealGesture)"))
    }

    private func readProjectSource(_ relativePath: String) throws -> String {
        let testsDir = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
        let projectRoot = testsDir.deletingLastPathComponent()
        return try String(contentsOf: projectRoot.appendingPathComponent(relativePath), encoding: .utf8)
    }

    private func extract(_ start: String, through end: String, from contents: String) throws -> String {
        let startRange = try XCTUnwrap(contents.range(of: start))
        let tail = contents[startRange.lowerBound...]
        let endRange = try XCTUnwrap(tail.range(of: end))
        return String(tail[..<endRange.upperBound])
    }
}
