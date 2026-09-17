import Foundation
import XCTest

final class MacPushReleaseContractTests: XCTestCase {
    func testReleaseScriptAcceptsAndEmbedsAnExplicitMacOSProfileBeforeOuterSigning() throws {
        let script = try readRepositoryFile("scripts/build-release.sh")

        XCTAssertTrue(script.contains("PING_MACOS_PROVISIONING_PROFILE"))
        XCTAssertTrue(script.contains("--macos-provisioning-profile"))
        XCTAssertTrue(script.contains("security cms -D -i"))
        XCTAssertTrue(script.contains("Contents/embedded.provisionprofile"))

        let copy = try XCTUnwrap(
            script.range(of: "embedded.provisionprofile")?.lowerBound,
            "release script must embed the validated macOS provisioning profile"
        )
        let outerSigning = try XCTUnwrap(
            script.range(of: "codesign --force --sign \"$SIGN_IDENTITY\"", range: copy..<script.endIndex)?.lowerBound,
            "release script must sign the outer app after embedding the profile"
        )
        XCTAssertLessThan(copy, outerSigning)
    }

    func testReleaseScriptValidatesTheMacOSProfileIdentityAndPlatformBeforeBuild() throws {
        let script = try readRepositoryFile("scripts/build-release.sh")
        let build = try XCTUnwrap(
            script.range(of: "xcodebuild ")?.lowerBound,
            "release script must build only after validating the supplied profile"
        )

        let requiredChecks = [
            "Print :Entitlements:com.apple.application-identifier",
            "if [ \"$PROFILE_APPLICATION_IDENTIFIER\" != \"878FAHTFQJ.com.youngminpark.ping.Ping\" ]; then",
            "Print :Entitlements:com.apple.developer.team-identifier",
            "if [ \"$PROFILE_TEAM_IDENTIFIER\" != \"878FAHTFQJ\" ]; then",
            "Print :Platform:0",
            "if [ \"$PROFILE_PLATFORM\" != \"OSX\" ]; then",
            "ExpirationDate",
            "PROFILE_EXPIRATION_EPOCH",
            "date -j -f \"%Y-%m-%dT%H:%M:%SZ\"",
            "Print :Entitlements:com.apple.developer.aps-environment",
            "if [ \"$PROFILE_APNS_ENV\" != \"production\" ]; then"
        ]

        for check in requiredChecks {
            let location = try XCTUnwrap(
                script.range(of: check)?.lowerBound,
                "release script must validate profile field: \(check)"
            )
            XCTAssertLessThan(location, build, "profile validation must happen before xcodebuild: \(check)")
        }
    }

    func testReleaseScriptRejectsMissingSparkleFrameworkInsteadOfSkippingItsSigning() throws {
        let script = try readRepositoryFile("scripts/build-release.sh")

        XCTAssertTrue(script.contains("if [ ! -d \"$SPARKLE_FRAMEWORK\" ]; then"))
        XCTAssertTrue(script.contains("Required Sparkle.framework missing"))
        XCTAssertFalse(script.contains("if [ -d \"$SPARKLE_FRAMEWORK\" ]; then"))

        let guardLocation = try XCTUnwrap(
            script.range(of: "if [ ! -d \"$SPARKLE_FRAMEWORK\" ]; then")?.lowerBound
        )
        let firstSparkleSigning = try XCTUnwrap(
            script.range(of: "sign_preserving_metadata \"$SPARKLE_FRAMEWORK/Versions/B/Autoupdate\"")?.lowerBound
        )
        XCTAssertLessThan(guardLocation, firstSparkleSigning)
    }

    func testReleaseScriptValidatesFinalProductionPushEntitlementAndKeepsDistributionChecks() throws {
        let script = try readRepositoryFile("scripts/build-release.sh")

        XCTAssertTrue(script.contains("codesign -d --entitlements :- \"$APP\" > \"$TMP_ENTITLEMENTS\""))
        XCTAssertTrue(script.contains("com.apple.developer.aps-environment"))
        XCTAssertTrue(script.contains("production"))
        XCTAssertTrue(script.contains("embedded.provisionprofile"))
        XCTAssertTrue(script.contains("codesign --verify --deep --strict --verbose=2 \"$APP\""))
        XCTAssertTrue(script.contains("xcrun notarytool submit"))
        XCTAssertTrue(script.contains("xcrun stapler staple"))
    }

    func testPushDocumentationDescribesTheCurrentMacOSContracts() throws {
        let spec = try readRepositoryFile("PING_PROJECT_SPECIFICATION.md")
        let readme = try readRepositoryFile("README.md")
        let backend = try readRepositoryFile("docs/PUSH_BACKEND_SETUP.md")

        for document in [spec, readme] {
            XCTAssertTrue(document.contains("APNs"))
            XCTAssertTrue(document.contains("영상"))
            XCTAssertTrue(document.contains("채팅"))
            XCTAssertTrue(document.contains("초대"))
            XCTAssertTrue(document.contains("600"))
            XCTAssertTrue(document.contains("실행 중"))
        }

        XCTAssertTrue(backend.contains("APNS_MACOS_BUNDLE_ID"))
        XCTAssertTrue(backend.contains("APNS_IOS_BUNDLE_ID"))
        XCTAssertTrue(backend.contains("APNS_WATCHOS_BUNDLE_ID"))
        XCTAssertTrue(backend.contains("invitations"))
        XCTAssertTrue(backend.contains("Vercel Hobby"))
        XCTAssertTrue(backend.contains("production"))
    }

    private func readRepositoryFile(_ relativePath: String) throws -> String {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        return try String(contentsOf: root.appendingPathComponent(relativePath), encoding: .utf8)
    }
}
