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
        XCTAssertTrue(source.contains("초대링크 복사"))
        XCTAssertTrue(source.contains("systemName: \"link\""))
        XCTAssertTrue(source.contains("Menu {"))
        XCTAssertTrue(source.contains(".menuIndicator(.hidden)"))
        XCTAssertFalse(source.contains("GlassButton(\"나가기\")"))
        XCTAssertFalse(source.contains("GlassButton(\"링크 복사\")"))
        XCTAssertFalse(source.contains("GlassButton(\"이름 변경\")"))
    }

    func testRoomListUsesBalancedHeaderButtonsAndBreathableRoomCards() throws {
        let source = try readSourceFile("Ping/UI/Setup/RoomListView.swift")

        XCTAssertTrue(source.contains("RoomHeaderActionButton"))
        XCTAssertTrue(source.contains(".frame(width: 144, height: 46)"))
        XCTAssertTrue(source.contains(".frame(maxWidth: .infinity, minHeight: 112"))
        XCTAssertTrue(source.contains("GridItem(.flexible(), spacing: 14)"))
        XCTAssertFalse(source.contains("GridItem(.flexible(), spacing: 14),\n        GridItem(.flexible(), spacing: 14)"))
    }

    func testRoomListHidesRoomLimitUntilUserReachesIt() throws {
        let source = try readSourceFile("Ping/UI/Setup/RoomListView.swift")

        XCTAssertFalse(source.contains("/\\(RoomLimits.maxRoomsPerUser)개 사용 중"))
        XCTAssertFalse(source.contains("개 사용 중"))
    }

    func testInviteLinkCreateRpcQualifiesRoomIdReferences() throws {
        let migration = try readSourceFile("20260518003000_room_capacity_limits.sql")

        XCTAssertTrue(migration.contains("from public.room_members rm_check"))
        XCTAssertTrue(migration.contains("rm_check.room_id = room_uuid"))
        XCTAssertTrue(migration.contains("from public.room_members rm_count"))
        XCTAssertTrue(migration.contains("rm_count.room_id = room_uuid"))
    }

    func testInviteLinkAcceptRpcQualifiesAmbiguousIdReferences() throws {
        let migration = try readSourceFile("20260519021000_fix_accept_invite_link_id_ambiguity.sql")

        XCTAssertTrue(migration.contains("create or replace function public.ping_accept_invite_link"))
        XCTAssertTrue(migration.contains("from public.rooms r_accept"))
        XCTAssertTrue(migration.contains("where r_accept.id = link_row.room_id"))
        XCTAssertTrue(migration.contains("update public.profiles p_accept"))
        XCTAssertTrue(migration.contains("where p_accept.id = current_uid"))
        XCTAssertTrue(migration.contains("update public.rooms r_update"))
        XCTAssertTrue(migration.contains("where r_update.id = link_row.room_id"))
        XCTAssertFalse(migration.contains("where id ="))
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

    func testInviteLinksUseCurrentProductionDomain() throws {
        let source = try readSourceFile("InviteLink.swift")
        let readme = try readSourceFile("README.md")
        let examplePlist = try readSourceFile("Supabase.example.plist")

        XCTAssertTrue(source.contains("https://0minping.vercel.app"))
        XCTAssertTrue(readme.contains("https://0minping.vercel.app"))
        XCTAssertTrue(examplePlist.contains("https://0minping.vercel.app"))
        XCTAssertFalse(source.contains("ping-0mininseoul.vercel.app"))
        XCTAssertFalse(readme.contains("ping-0mininseoul.vercel.app"))
        XCTAssertFalse(examplePlist.contains("ping-0mininseoul.vercel.app"))
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
