import XCTest

final class ChatComposerIMEContractTests: XCTestCase {
    func testComposerDoesNotOverwriteMarkedTextDuringIMEComposition() throws {
        let source = try readSourceFile("Ping/UI/History/ChatComposerView.swift")
        let update = try sourceSlice(
            in: source,
            from: "func updateNSView(_ scroll: NSScrollView, context: Context)",
            to: "private func recalculateHeight"
        )

        XCTAssertTrue(update.contains("context.coordinator.parent = self"))
        let markedTextGuard = try XCTUnwrap(update.range(of: "guard !textView.hasMarkedText() else"))
        let stringAssignment = try XCTUnwrap(update.range(of: "if textView.string != text"))
        XCTAssertTrue(markedTextGuard.lowerBound < stringAssignment.lowerBound)
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
}
