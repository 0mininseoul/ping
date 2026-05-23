import XCTest

final class EntitlementsTests: XCTestCase {
    func testMacSandboxUsesAudioInputEntitlementForMicrophoneAccess() throws {
        let entitlements = try readPlist("Ping.entitlements")

        XCTAssertEqual(entitlements["com.apple.security.app-sandbox"] as? Bool, true)
        XCTAssertEqual(entitlements["com.apple.security.device.audio-input"] as? Bool, true)
        XCTAssertNil(entitlements["com.apple.security.device.microphone"])
    }

    func testProjectConfigurationUsesAudioInputEntitlement() throws {
        let project = try readSourceFile("project.yml")

        XCTAssertTrue(project.contains("CODE_SIGN_ENTITLEMENTS: Ping.entitlements"))
        XCTAssertTrue(project.contains("CODE_SIGN_ENTITLEMENTS: PingDebug.entitlements"))
        XCTAssertTrue(project.contains("OTHER_CODE_SIGN_FLAGS: \"--requirements '=designated => identifier \\\"com.youngminpark.ping.Ping\\\"'\""))
        XCTAssertTrue(project.contains("NSCameraUsageDescription: \"Ping은 3초 영상 메시지 촬영을 위해 카메라를 사용합니다.\""))
        XCTAssertFalse(project.contains("NSCameraUsageDescription: \"Ping은 2초"))
        XCTAssertFalse(project.contains("com.apple.security.device.microphone: true"))
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
