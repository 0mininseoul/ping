import XCTest

final class InviteLinkContractTests: XCTestCase {
    func testSupabaseMigrationDefinesInviteLinksAndRPCs() throws {
        let migration = try readSourceFile("supabase/migrations/20260517000100_create_ping_backend.sql")

        XCTAssertTrue(migration.contains("create table if not exists public.invite_links"))
        XCTAssertTrue(migration.contains("ping_create_invite_link"))
        XCTAssertTrue(migration.contains("ping_accept_invite_link"))
    }

    func testInvitationServiceCreatesAndAcceptsInviteLinks() throws {
        let source = try readSourceFile("Ping/Backend/InvitationService.swift")

        XCTAssertTrue(source.contains("createInviteLink"))
        XCTAssertTrue(source.contains("acceptInviteLink"))
        XCTAssertTrue(source.contains("ping_create_invite_link"))
        XCTAssertTrue(source.contains("ping_accept_invite_link"))
    }

    func testRoomListExposesCopyInviteLinkAction() throws {
        let source = try readSourceFile("Ping/UI/Setup/RoomListView.swift")

        XCTAssertTrue(source.contains("onCopyInviteLink"))
        XCTAssertTrue(source.contains("링크 복사"))
    }

    func testRoomSearchCanJoinByInviteLinkOrCode() throws {
        let source = try readSourceFile("Ping/UI/Setup/RoomSearchView.swift")

        XCTAssertTrue(source.contains("onJoinInviteLink"))
        XCTAssertTrue(source.contains("초대 링크로 참여"))
        XCTAssertTrue(source.contains("PingInviteLink.token"))
    }

    func testAppRegistersPingInviteURLScheme() throws {
        let project = try readSourceFile("project.yml")
        let appDelegate = try readSourceFile("Ping/AppDelegate.swift")

        XCTAssertTrue(project.contains("CFBundleURLSchemes"))
        XCTAssertTrue(project.contains("- ping"))
        XCTAssertTrue(appDelegate.contains("application(_ application: NSApplication, open urls: [URL])"))
        XCTAssertTrue(appDelegate.contains("acceptInviteLink(token:"))
    }

    func testAppDefersInviteAcceptanceUntilBootstrapFinishesForExistingUsers() throws {
        let appDelegate = try readSourceFile("Ping/AppDelegate.swift")

        XCTAssertTrue(appDelegate.contains("startBootstrapTaskIfNeeded()"))
        XCTAssertTrue(appDelegate.contains("consumePendingInviteTokenIfAvailable()"))
        XCTAssertFalse(appDelegate.contains("if let uid = SupabaseClient.shared.currentUid {\n                showOnboarding(uid: uid)\n            }"))
    }

    func testLandingInviteRouteOffersPingDeepLinkForInstalledApp() throws {
        let source = try readSourceFile("App.tsx")

        XCTAssertTrue(source.contains("ping://invite/"))
        XCTAssertTrue(source.contains("Ping에서 열기"))
    }

    func testReleaseScriptPackagesDownloadAndFailsWithoutSupabaseConfig() throws {
        let script = try readSourceFile("build-release.sh")

        XCTAssertTrue(script.contains("Resources/Supabase.plist"))
        XCTAssertTrue(script.contains("Supabase.plist is required"))
        XCTAssertTrue(script.contains("web/public/downloads"))
        XCTAssertTrue(script.contains("Ping-v$VERSION.dmg"))
    }

    func testGitignoreKeepsDownloadDmgTrackable() throws {
        let gitignore = try readSourceFile(".gitignore")

        XCTAssertTrue(gitignore.contains("!web/public/downloads/*.dmg"))
    }

    private func readSourceFile(_ relativePath: String) throws -> String {
        let fileName = URL(fileURLWithPath: relativePath).lastPathComponent
        let fileURL = try XCTUnwrap(Bundle(for: Self.self).resourceURL?.appendingPathComponent(fileName))

        return try String(contentsOf: fileURL, encoding: .utf8)
    }
}
