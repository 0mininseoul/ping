import XCTest

final class DesktopPresenceContractTests: XCTestCase {
    func testBackendDefinesDesktopPresenceHeartbeatContract() throws {
        let migration = try readSourceFile("supabase/migrations/20260701000100_desktop_presence.sql")

        XCTAssertTrue(migration.contains("create table if not exists public.desktop_presence"))
        XCTAssertTrue(migration.contains("primary key (uid, device_id)"))
        XCTAssertTrue(migration.contains("active_room_id uuid"))
        XCTAssertTrue(migration.contains("create or replace function public.ping_update_desktop_presence"))
        XCTAssertTrue(migration.contains("create or replace function public.ping_clear_desktop_presence"))
    }

    /// 같은 방 멤버의 맥이 켜져 있는지 보여주려면 남의 행을 읽을 수 있어야 한다.
    /// desktop_presence의 RLS는 본인 행만 허용하므로 노출은 RPC로만 한다.
    func testBackendExposesRoomMemberPresence() throws {
        let migration = try readSourceFile("supabase/migrations/20260914000100_desktop_presence_visibility.sql")

        XCTAssertTrue(migration.contains("create or replace function public.ping_room_desktop_presence"))
        XCTAssertTrue(migration.contains("security definer"))
        // 호출자가 속한 방의 멤버만 돌려줘야 한다.
        XCTAssertTrue(migration.contains("from public.room_members"))
        XCTAssertTrue(migration.contains("grant execute on function public.ping_room_desktop_presence(uuid[]) to authenticated"))
        // 남의 행을 직접 select하게 풀어주면 안 된다.
        XCTAssertFalse(migration.contains("create policy desktop_presence_select_room_members"))
    }

    /// "마지막 접속 시각"을 보여주려면 종료 시 행을 지우면 안 된다.
    func testClearingPresenceKeepsTheLastSeenRow() throws {
        let migration = try readSourceFile("supabase/migrations/20260914000100_desktop_presence_visibility.sql")

        XCTAssertTrue(migration.contains("add column if not exists ended_at timestamptz"))
        XCTAssertTrue(migration.contains("create or replace function public.ping_clear_desktop_presence"))
        XCTAssertTrue(migration.contains("set ended_at = now()"))
        XCTAssertFalse(migration.contains("delete from public.desktop_presence"))
        // 앱을 다시 켜면 같은 행이 되살아나야 한다.
        XCTAssertTrue(migration.contains("ended_at = null"))
    }

    /// 종료한 기기를 "켜져 있음"으로 읽으면 Ping을 끈 뒤에도 최대 45초간
    /// 휴대폰 푸시가 억제된다. 예전엔 행을 지워서 즉시 풀렸다.
    func testPushIgnoresEndedDesktopSessions() throws {
        let push = try readSourceFile("api/push.ts")

        XCTAssertTrue(push.contains(".is('ended_at', null)"))
    }

    func testMacAppPublishesDesktopPresenceHeartbeat() throws {
        let service = try readSourceFile("Ping/Backend/DesktopPresenceService.swift")
        let appDelegate = try readSourceFile("Ping/AppDelegate.swift")

        XCTAssertTrue(service.contains("ping_update_desktop_presence"))
        XCTAssertTrue(service.contains("ping_clear_desktop_presence"))
        XCTAssertTrue(service.contains("active_room_uuid"))
        XCTAssertTrue(appDelegate.contains("private let desktopPresenceService = DesktopPresenceService()"))
        XCTAssertTrue(appDelegate.contains("startDesktopPresenceHeartbeat()"))
        XCTAssertTrue(appDelegate.contains("desktopPresenceTask?.cancel()"))
    }

    func testPushSuppressesMobileWhenDesktopPresenceIsFresh() throws {
        let push = try readSourceFile("api/push.ts")

        XCTAssertTrue(push.contains("freshDesktopPresenceUids"))
        XCTAssertTrue(push.contains(".from('desktop_presence')"))
        XCTAssertTrue(push.contains("PUSH_DESKTOP_PRESENCE_TTL_SECONDS"))
        XCTAssertTrue(push.contains("selectPushTokens"))
    }

    /// 멤버 팝오버는 열려 있는 동안에만 상태를 갱신한다. 평상시에 폴링하면
    /// 6명짜리 서비스에 쓸데없는 요청만 쌓인다.
    func testMembersPopoverShowsPresenceWhileOpen() throws {
        let source = try readSourceFile("Ping/UI/Setup/RoomDetailView.swift")

        XCTAssertTrue(source.contains("PresenceStore.shared"))
        XCTAssertTrue(source.contains("presenceStore.refresh(roomIds: [roomId])"))
        XCTAssertTrue(source.contains("DesktopPresencePolicy.lastSeenText("))
    }

    /// 메뉴바는 방에 종속되지 않으니 내 모든 방의 멤버를 합쳐 보여준다.
    func testStatusMenuListsLiveMembers() throws {
        let menu = try readSourceFile("Ping/StatusMenuBuilder.swift")
        let appDelegate = try readSourceFile("Ping/AppDelegate.swift")

        XCTAssertTrue(menu.contains("presenceItemTag"))
        XCTAssertTrue(menu.contains("static func presenceTitle("))
        XCTAssertTrue(appDelegate.contains("refreshStatusMenuPresence()"))
        XCTAssertTrue(appDelegate.contains("DesktopPresencePolicy.liveMemberNames("))
        // 메뉴를 열 때 조회한다. 상시 폴링이 아니다.
        XCTAssertTrue(appDelegate.contains("func menuWillOpen("))
    }

    func testSelectedRealtimeChatIsMarkedReadAgain() throws {
        let source = try readSourceFile("Ping/UI/History/HistoryViewModel.swift")
        let chatService = try readSourceFile("Ping/Backend/ChatMessageService.swift")

        XCTAssertTrue(source.contains("markSelectedRoomReadAfterRealtime(roomId: msg.roomId)"))
        XCTAssertTrue(source.contains("try await chatService.markRoomChatRead(roomId: roomId)"))
        XCTAssertTrue(chatService.contains("func markRoomChatRead(roomId: String) async throws"))
        XCTAssertTrue(chatService.contains("\"ping_mark_room_chat_read\""))
        XCTAssertTrue(source.contains("appState.markRoomReadLocally(roomId: roomId)"))
    }

    private func readSourceFile(_ relativePath: String) throws -> String {
        let testsDir = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
        let projectRoot = testsDir.deletingLastPathComponent()
        return try String(contentsOf: projectRoot.appendingPathComponent(relativePath), encoding: .utf8)
    }
}
