import XCTest

final class ReleaseVersionContractTests: XCTestCase {
    // The released macOS version lives in exactly one place — project.yml's
    // MARKETING_VERSION. Every user-facing reference must agree with it so a
    // release can't half-ship (e.g. the appcast advertising the new version
    // while the website still links the old DMG). Deriving the expected version
    // from project.yml — instead of pinning a hardcoded number — means this
    // contract enforces consistency without needing a hand-edit every release.
    func testReleaseVersionIsConsistentAcrossUserFacingFiles() throws {
        let project = try readSourceFile("project.yml")
        let routes = try readSourceFile("routes.tsx")
        let readme = try readSourceFile("README.md")

        let version = try marketingVersion(in: project)

        XCTAssertTrue(
            routes.contains("MAC_APP_VERSION = \"v\(version)\""),
            "routes.tsx MAC_APP_VERSION must match project.yml MARKETING_VERSION (v\(version))"
        )
        XCTAssertTrue(
            routes.contains("MAC_DOWNLOAD_URL = \"/downloads/Ping-v\(version).dmg\""),
            "routes.tsx MAC_DOWNLOAD_URL must point at /downloads/Ping-v\(version).dmg"
        )
        XCTAssertTrue(
            readme.contains("Ping-v\(version).dmg"),
            "README must reference the released Ping-v\(version).dmg"
        )

        // Windows ships on its own cadence; keep its references self-consistent.
        XCTAssertTrue(routes.contains("WINDOWS_APP_VERSION = \"v0.3.28\""))
        XCTAssertTrue(routes.contains("WINDOWS_DOWNLOAD_URL = \"/downloads/windows/PingSetup-v0.3.28.exe\""))
    }

    /// Extracts the value of `MARKETING_VERSION: "x.y.z"` from project.yml.
    private func marketingVersion(in projectYml: String) throws -> String {
        let value = projectYml
            .split(separator: "\n")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .first { $0.hasPrefix("MARKETING_VERSION:") }
            .flatMap { line -> String? in
                guard let open = line.firstIndex(of: "\""),
                      let close = line.lastIndex(of: "\""),
                      open < close else { return nil }
                return String(line[line.index(after: open)..<close])
            }
        return try XCTUnwrap(value, "MARKETING_VERSION not found in project.yml")
    }

    private func readSourceFile(_ relativePath: String) throws -> String {
        let fileName = URL(fileURLWithPath: relativePath).lastPathComponent
        let fileURL = try XCTUnwrap(Bundle(for: Self.self).resourceURL?.appendingPathComponent(fileName))

        return try String(contentsOf: fileURL, encoding: .utf8)
    }
}
