import XCTest

final class ReleaseVersionContractTests: XCTestCase {
    func testCurrentReleaseVersionIsBumpedForSparkleUpdate() throws {
        let project = try readSourceFile("project.yml")
        let routes = try readSourceFile("routes.tsx")
        let readme = try readSourceFile("README.md")

        XCTAssertTrue(project.contains("MARKETING_VERSION: \"0.3.29\""))
        XCTAssertTrue(project.contains("CURRENT_PROJECT_VERSION: \"41\""))
        XCTAssertTrue(routes.contains("MAC_APP_VERSION = \"v0.3.29\""))
        XCTAssertTrue(routes.contains("WINDOWS_APP_VERSION = \"v0.3.28\""))
        XCTAssertTrue(routes.contains("MAC_DOWNLOAD_URL = \"/downloads/Ping-v0.3.29.dmg\""))
        XCTAssertTrue(routes.contains("WINDOWS_DOWNLOAD_URL = \"/downloads/windows/PingSetup-v0.3.28.exe\""))
        XCTAssertTrue(readme.contains("Ping-v0.3.29.dmg"))
    }

    private func readSourceFile(_ relativePath: String) throws -> String {
        let fileName = URL(fileURLWithPath: relativePath).lastPathComponent
        let fileURL = try XCTUnwrap(Bundle(for: Self.self).resourceURL?.appendingPathComponent(fileName))

        return try String(contentsOf: fileURL, encoding: .utf8)
    }
}
