import XCTest

final class LandingPageDesignContractTests: XCTestCase {
    func testFinalDownloadCardAvoidsVignetteAuroraLayer() throws {
        let source = try readSourceFile("FinalCTA.tsx")

        XCTAssertFalse(source.contains("Aurora"))
        XCTAssertFalse(source.contains("bg-gradient-to-t"))
        XCTAssertFalse(source.contains("var(--shadow-card)"))
        XCTAssertTrue(source.contains("bg-bg-elev"))
        XCTAssertTrue(source.contains("shadow-[0_18px_42px_rgba(10,11,9,0.07)]"))
    }

    private func readSourceFile(_ relativePath: String) throws -> String {
        let fileName = URL(fileURLWithPath: relativePath).lastPathComponent
        let fileURL = try XCTUnwrap(Bundle(for: Self.self).resourceURL?.appendingPathComponent(fileName))

        return try String(contentsOf: fileURL, encoding: .utf8)
    }
}
