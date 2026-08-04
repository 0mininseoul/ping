import XCTest

final class AutoStartAgentPlistTests: XCTestCase {
    func testAgentRelaunchesOnlyOnAbnormalExit() throws {
        let plist = try readPlist("com.youngminpark.ping.Ping.keepalive.plist")
        let keepAlive = try XCTUnwrap(plist["KeepAlive"] as? [String: Any])

        // 사용자가 "종료"하면 exit(0)이므로 되살아나면 안 된다.
        XCTAssertEqual(keepAlive["SuccessfulExit"] as? Bool, false)
        XCTAssertEqual(plist["RunAtLoad"] as? Bool, true)
    }

    func testAgentUsesBundleRelativeProgramPath() throws {
        let plist = try readPlist("com.youngminpark.ping.Ping.keepalive.plist")

        // 절대 경로면 앱을 옮겼을 때 깨진다.
        XCTAssertEqual(plist["BundleProgram"] as? String, "Contents/MacOS/Ping")
        XCTAssertNil(plist["ProgramArguments"])
    }

    func testAgentIdentityMatchesController() throws {
        let plist = try readPlist("com.youngminpark.ping.Ping.keepalive.plist")

        XCTAssertEqual(plist["Label"] as? String, "com.youngminpark.ping.Ping.keepalive")
        XCTAssertEqual(plist["ThrottleInterval"] as? Int, 30)
        XCTAssertEqual(
            plist["AssociatedBundleIdentifiers"] as? [String],
            ["com.youngminpark.ping.Ping"]
        )
    }

    func testProjectBundlesAgentIntoLaunchAgentsDirectory() throws {
        let project = try readSourceFile("project.yml")

        XCTAssertTrue(project.contains("subpath: Contents/Library/LaunchAgents"))
        XCTAssertTrue(project.contains("Resources/LaunchAgents/com.youngminpark.ping.Ping.keepalive.plist"))
    }

    private func readPlist(_ relativePath: String) throws -> [String: Any] {
        let data = try Data(contentsOf: resourceURL(for: relativePath))
        let plist = try PropertyListSerialization.propertyList(from: data, format: nil)

        return try XCTUnwrap(plist as? [String: Any])
    }

    private func readSourceFile(_ relativePath: String) throws -> String {
        try String(contentsOf: resourceURL(for: relativePath), encoding: .utf8)
    }

    private func resourceURL(for relativePath: String) throws -> URL {
        let fileName = URL(fileURLWithPath: relativePath).lastPathComponent
        return try XCTUnwrap(Bundle(for: Self.self).resourceURL?.appendingPathComponent(fileName))
    }
}
