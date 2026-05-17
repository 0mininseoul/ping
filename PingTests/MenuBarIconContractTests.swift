import XCTest

final class MenuBarIconContractTests: XCTestCase {
    func testMenuBarIconUsesColorAssetInsteadOfTemplateRendering() throws {
        let appDelegate = try readSourceFile("Ping/AppDelegate.swift")
        let generator = try readSourceFile("scripts/generate-icons.swift")

        XCTAssertTrue(appDelegate.contains("menuIcon?.isTemplate = false"))
        XCTAssertFalse(appDelegate.contains("menuIcon?.isTemplate = true"))
        XCTAssertFalse(generator.contains("\"template-rendering-intent\" : \"template\""))
    }

    func testMenuBarIconGeneratorDrawsMinimalLensAsset() throws {
        let generator = try readSourceFile("scripts/generate-icons.swift")

        XCTAssertTrue(generator.contains("writeMenuBarLensIcon"))
        XCTAssertTrue(generator.contains("lensOuterRing"))
        XCTAssertTrue(generator.contains("blueCatchlight"))
        XCTAssertFalse(generator.contains("mintTop"))
    }

    private func readSourceFile(_ relativePath: String) throws -> String {
        let fileName = URL(fileURLWithPath: relativePath).lastPathComponent
        let fileURL = try XCTUnwrap(Bundle(for: Self.self).resourceURL?.appendingPathComponent(fileName))

        return try String(contentsOf: fileURL, encoding: .utf8)
    }
}
