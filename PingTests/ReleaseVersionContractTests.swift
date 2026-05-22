import XCTest

final class ReleaseVersionContractTests: XCTestCase {
    func testCurrentReleaseVersionIsBumpedForSparkleUpdate() throws {
        let project = try readSourceFile("project.yml")
        let routes = try readSourceFile("routes.tsx")
        let readme = try readSourceFile("README.md")

        XCTAssertTrue(project.contains("MARKETING_VERSION: \"0.3.8\""))
        XCTAssertTrue(project.contains("CURRENT_PROJECT_VERSION: \"17\""))
        XCTAssertTrue(routes.contains("APP_VERSION = \"v0.3.8\""))
        XCTAssertTrue(routes.contains("DOWNLOAD_URL = \"/downloads/Ping-v0.3.8.dmg\""))
        XCTAssertTrue(readme.contains("Ping-v0.3.8.dmg"))
    }

    private func readSourceFile(_ relativePath: String) throws -> String {
        let fileName = URL(fileURLWithPath: relativePath).lastPathComponent
        let fileURL = try XCTUnwrap(Bundle(for: Self.self).resourceURL?.appendingPathComponent(fileName))

        return try String(contentsOf: fileURL, encoding: .utf8)
    }
}
