import XCTest

final class RoomManagerUXContractTests: XCTestCase {
    func testEmptyRoomStateOffersCreateAndFindActions() throws {
        let source = try readSourceFile("Ping/UI/Setup/RoomListView.swift")

        XCTAssertTrue(source.contains("onCreateRoom"))
        XCTAssertTrue(source.contains("onFindRoom"))
        XCTAssertTrue(source.contains("룸 만들기"))
        XCTAssertTrue(source.contains("룸 찾기"))
    }

    func testEmptyRoomStateDoesNotUseNestedGlassPanel() throws {
        let source = try readSourceFile("Ping/UI/Setup/RoomListView.swift")
        let emptyState = try sourceSlice(
            in: source,
            from: "private var emptyState",
            to: "private func roomCard"
        )

        XCTAssertFalse(emptyState.contains("GlassPanel"))
        XCTAssertFalse(emptyState.contains(".glassEffect()"))
    }

    func testRoomManagerCanCreateRoomFromRoomsTab() throws {
        let source = try readSourceFile("Ping/UI/Setup/RoomManagerWindow.swift")

        // Room manager provides create and search actions via titlebar controls scoped to the window.
        XCTAssertTrue(source.contains("createRoom()"))
        XCTAssertTrue(source.contains("roomService.createRoom"))
        XCTAssertTrue(source.contains("새 룸 만들기"))
        XCTAssertTrue(source.contains("룸 찾기"))
        XCTAssertTrue(source.contains("RoomManagerToolbarNotification.createRoom"))
        XCTAssertTrue(source.contains("RoomManagerToolbarNotification.searchRoom"))
    }

    func testRoomManagerTitlebarActionsStayWindowScopedInsteadOfSidebarScoped() throws {
        let source = try readSourceFile("Ping/UI/Setup/RoomManagerWindow.swift")
        let sidebar = try sourceSlice(
            in: source,
            from: "private var sidebarContent",
            to: "private var detailContent"
        )
        let window = try sourceSlice(
            in: source,
            from: "final class RoomManagerWindow",
            to: "enum RoomManagerTab"
        )

        XCTAssertTrue(window.contains("NSTitlebarAccessoryViewController"))
        XCTAssertTrue(window.contains("layoutAttribute = .right"))
        XCTAssertTrue(window.contains("RoomManagerTitlebarActionHandler.makeAccessoryView"))
        XCTAssertTrue(window.contains("NSApp.sendAction(#selector(NSSplitViewController.toggleSidebar"))
        XCTAssertTrue(window.contains("suppressDefaultSidebarToolbar()"))
        XCTAssertTrue(window.contains("override var toolbar: NSToolbar?"))
        XCTAssertTrue(window.contains("isSuppressingDefaultToolbar"))
        XCTAssertTrue(window.contains("self?.toolbar = nil"))
        XCTAssertTrue(source.contains("toolbar(removing: .sidebarToggle)"))
        XCTAssertTrue(source.contains(".toolbar(.hidden, for: .windowToolbar)"))
        XCTAssertFalse(sidebar.contains(".toolbar"))
    }

    func testRoomSidebarUsesCompactWidthThatGrowsWithCappedRoomNames() throws {
        let roomManagerSource = try readSourceFile("Ping/UI/Setup/RoomManagerWindow.swift")
        let roomListSource = try readSourceFile("Ping/UI/Setup/RoomListView.swift")
        let roomDetailSource = try readSourceFile("Ping/UI/Setup/RoomDetailView.swift")
        let pairingViewSource = try readSourceFile("Ping/UI/Setup/PairingView.swift")
        let pairingViewModelSource = try readSourceFile("Ping/UI/Setup/PairingViewModel.swift")

        XCTAssertTrue(roomManagerSource.contains("private var sidebarWidth"))
        XCTAssertTrue(roomManagerSource.contains(".navigationSplitViewColumnWidth(min: 148, ideal: sidebarWidth, max: 240)"))
        XCTAssertTrue(roomManagerSource.contains("RoomLimits.sanitizedRoomName($0.name).count"))
        XCTAssertTrue(roomManagerSource.contains("RoomLimits.sanitizedRoomName(room.name)"))
        XCTAssertTrue(roomListSource.contains("limitRoomNameInput"))
        XCTAssertTrue(roomListSource.contains("RoomLimits.sanitizedRoomName(editingName)"))
        XCTAssertTrue(roomDetailSource.contains("limitRoomNameInput"))
        XCTAssertTrue(roomDetailSource.contains("RoomLimits.sanitizedRoomName(editingRoomName)"))
        XCTAssertTrue(pairingViewSource.contains("RoomLimits.maxRoomNameLength"))
        XCTAssertTrue(pairingViewSource.contains(".onChange(of: text.wrappedValue)"))
        XCTAssertTrue(pairingViewModelSource.contains("RoomLimits.isValidRoomName(roomName)"))
        XCTAssertTrue(pairingViewModelSource.contains("startAction = .createRoom(name: sanitizedRoomName)"))
    }

    func testRoomManagerRestoresAValidRoomSelectionWhenOpened() throws {
        let source = try readSourceFile("Ping/UI/Setup/RoomManagerWindow.swift")

        XCTAssertTrue(source.contains("selectInitialRoomIfNeeded()"))
        XCTAssertTrue(source.contains("appState.lastSelectedRoomId"))
        XCTAssertTrue(source.contains("appState.defaultRoom?.id"))
        XCTAssertTrue(source.contains("appState.rooms.contains(where: { $0.id == selectedRoomId })"))
    }

    func testHistoryTimelineUsesLocalThumbnailsWithoutRemoteFetchForCollapsedRows() throws {
        let messageRowSource = try readSourceFile("Ping/UI/History/MessageRowView.swift")
        let thumbnailSource = try readSourceFile("Ping/UI/History/VideoThumbnailView.swift")
        let inlineSource = try readSourceFile("Ping/UI/History/InlinePlayerView.swift")
        let collapsedThumbnail = try sourceSlice(
            in: messageRowSource,
            from: "private var thumbnail",
            to: "private var thumbnailSize"
        )

        XCTAssertTrue(collapsedThumbnail.contains("VideoThumbnailView"))
        XCTAssertTrue(collapsedThumbnail.contains("allowsRemoteFetch: false"))
        XCTAssertTrue(thumbnailSource.contains("LocalArchive.existingVideoURL"))
        XCTAssertTrue(inlineSource.contains("LocalArchive.existingVideoURL"))
    }

    func testVideoRowsDoNotRenderRedundantModeDotBelowThumbnails() throws {
        let source = try readSourceFile("Ping/UI/History/MessageRowView.swift")

        XCTAssertFalse(source.contains("circle.fill"))
        XCTAssertFalse(source.contains("rectangle.fill"))
    }

    func testTimestampRevealSpringsBackAndKeepsGapFromBubble() throws {
        let source = try readSourceFile("Ping/UI/History/RoomTimelineView.swift")
        let scrollMonitor = try sourceSlice(
            in: source,
            from: "scrollWheelMonitor = NSEvent.addLocalMonitorForEvents",
            to: ".simultaneousGesture"
        )

        XCTAssertTrue(source.contains("@State private var revealResetTask"))
        XCTAssertTrue(source.contains("private let timestampGap: CGFloat = 16"))
        XCTAssertTrue(source.contains("private let timestampWidth: CGFloat = 78"))
        XCTAssertTrue(source.contains(".offset(x: timestampGap)"))
        XCTAssertTrue(scrollMonitor.contains("scheduleRevealReset()"))
        XCTAssertTrue(scrollMonitor.contains("resetRevealOffset()"))
    }

    func testChatComposerUsesCommandEnterForSendAndPlainEnterForNewline() throws {
        let source = try readSourceFile("Ping/UI/History/RoomTimelineView.swift")
        let monitor = try sourceSlice(
            in: source,
            from: "composerKeyMonitor = NSEvent.addLocalMonitorForEvents",
            to: ".onDisappear"
        )

        XCTAssertTrue(monitor.contains("flags == .command"))
        XCTAssertFalse(monitor.contains("flags.isEmpty || flags == .command"))
    }

    func testEmptyTimelineShowsAQuietEmptyState() throws {
        let source = try readSourceFile("Ping/UI/History/RoomTimelineView.swift")

        XCTAssertTrue(source.contains("emptyTimelineState"))
        XCTAssertTrue(source.contains("viewModel.groups.isEmpty, !viewModel.isLoading"))
        XCTAssertTrue(source.contains("\"아직 기록 없음\""))
    }

    func testRoomDetailRenameUsesInlineHeaderEditorInsteadOfAlert() throws {
        let source = try readSourceFile("Ping/UI/Setup/RoomDetailView.swift")
        let renameSection = try sourceSlice(
            in: source,
            from: "private func inlineRoomNameEditor",
            to: "private func leaveRoom"
        )

        XCTAssertTrue(renameSection.contains("TextField(\"\", text: $editingRoomName)"))
        XCTAssertTrue(source.contains("Button(action: { beginRenaming(room) })"))
        XCTAssertTrue(renameSection.contains("commitRename(room)"))
        XCTAssertTrue(renameSection.contains("renameLocalRoom(roomId: roomId, newName: newName)"))
        XCTAssertFalse(renameSection.contains("NSAlert"))
        XCTAssertFalse(renameSection.contains("runModal"))
    }

    func testRoomCreateAndInlineRenameUpdateLocalRoomsWithoutWaitingForPolling() throws {
        let roomManagerSource = try readSourceFile("Ping/UI/Setup/RoomManagerWindow.swift")
        let roomListSource = try readSourceFile("Ping/UI/Setup/RoomListView.swift")

        XCTAssertTrue(roomManagerSource.contains("insertOrReplaceRoom"))
        XCTAssertTrue(roomManagerSource.contains("let createdRoom = try await roomService.createRoom"))
        XCTAssertTrue(roomListSource.contains("renameLocalRoom"))
        XCTAssertTrue(roomListSource.contains("renameLocalRoom(roomId: roomId, newName: newName)"))
    }

    func testUserInviteUsesAtomicReuseRpcInsteadOfCreatingDuplicateRooms() throws {
        let appDelegateSource = try readSourceFile("Ping/AppDelegate.swift")
        let invitationServiceSource = try readSourceFile("Ping/Backend/InvitationService.swift")
        let migration = try readSourceFile("20260518113000_invite_user_reuses_pending_room.sql")
        let handleInvite = try sourceSlice(
            in: appDelegateSource,
            from: "private func handleInvite(user: PingUser)",
            to: "private func copyInviteLink"
        )

        XCTAssertTrue(handleInvite.contains("invitationService.inviteUser"))
        XCTAssertTrue(handleInvite.contains("insertOrReplaceRoom(room)"))
        XCTAssertFalse(handleInvite.contains("roomService.createRoom"))
        XCTAssertTrue(invitationServiceSource.contains("func inviteUser"))
        XCTAssertTrue(invitationServiceSource.contains("ping_invite_user"))
        XCTAssertTrue(migration.contains("create or replace function public.ping_invite_user"))
        XCTAssertTrue(migration.contains("existing_invitation_id"))
        XCTAssertTrue(migration.contains("existing_room_id"))
        XCTAssertTrue(migration.contains("grant execute on function public.ping_invite_user"))
    }

    func testUserSearchShowsExistingMembersAsMyRoomInsteadOfInvite() throws {
        let source = try readSourceFile("Ping/UI/Setup/RoomSearchView.swift")

        XCTAssertTrue(source.contains("sharesRoom(with: user)"))
        XCTAssertTrue(source.contains("sharesExistingRoom ? \"내 룸\" : \"초대\""))
        XCTAssertTrue(source.contains(".disabled(sharesExistingRoom || user.id == nil)"))
    }

    func testRoomMenuOffersRenameForMemberRooms() throws {
        let source = try readSourceFile("Ping/UI/Setup/RoomListView.swift")
        let roomActions = try sourceSlice(
            in: source,
            from: "private func roomActions(for room: Room)",
            to: "private func iconAction"
        )

        XCTAssertTrue(roomActions.contains("Button(\"이름 변경\")"))
        XCTAssertFalse(roomActions.contains("if isOwner(room)"))
    }

    func testRoomRenameUsesInlineCardEditorInsteadOfPromptWindow() throws {
        let roomListSource = try readSourceFile("Ping/UI/Setup/RoomListView.swift")
        let roomManagerSource = try readSourceFile("Ping/UI/Setup/RoomManagerWindow.swift")

        XCTAssertTrue(roomListSource.contains("@State private var editingRoomId"))
        XCTAssertTrue(roomListSource.contains("@FocusState private var focusedEditingRoomId"))
        XCTAssertTrue(roomListSource.contains("private func inlineRoomNameEditor"))
        XCTAssertTrue(roomListSource.contains("TextField(\"\", text: $editingName)"))
        XCTAssertTrue(roomListSource.contains("beginRenaming(room)"))
        XCTAssertTrue(roomListSource.contains("commitRename(room)"))
        XCTAssertTrue(roomListSource.contains("onExitCommand"))

        XCTAssertFalse(roomManagerSource.contains("onRename: renameRoom"))
        XCTAssertFalse(roomManagerSource.contains("private func renameRoom"))
        XCTAssertFalse(roomManagerSource.contains("\"룸 이름 변경\""))
    }

    func testRoomRenameAllowsAnyCurrentMember() throws {
        let source = try readSourceFile("Ping/UI/Setup/RoomListView.swift")
        let commitRename = try sourceSlice(
            in: source,
            from: "private func commitRename(_ room: Room)",
            to: "private func renameLocalRoom"
        )

        XCTAssertTrue(commitRename.contains("room.memberUids.contains(currentUid)"))
        XCTAssertTrue(commitRename.contains("roomService.renameRoom(roomId: roomId, newName: newName)"))
        XCTAssertFalse(commitRename.contains("room.ownerUid == appState.currentUser?.id"))
    }

    func testRoomRenameRpcAuthorizesByMembershipInsteadOfOwnership() throws {
        let migration = try readSourceFile("20260517000100_create_ping_backend.sql")
        let renameRpc = try sourceSlice(
            in: migration,
            from: "create or replace function public.ping_rename_room",
            to: "create or replace function public.ping_search_profiles"
        )

        XCTAssertTrue(renameRpc.contains("from public.room_members"))
        XCTAssertTrue(renameRpc.contains("where room_id = room_uuid"))
        XCTAssertFalse(renameRpc.contains("rooms.owner_uid = current_uid"))
    }

    private func readSourceFile(_ relativePath: String) throws -> String {
        let fileName = URL(fileURLWithPath: relativePath).lastPathComponent
        let fileURL = try XCTUnwrap(Bundle(for: Self.self).resourceURL?.appendingPathComponent(fileName))

        return try String(contentsOf: fileURL, encoding: .utf8)
    }

    private func sourceSlice(in source: String, from startMarker: String, to endMarker: String) throws -> String {
        let start = try XCTUnwrap(source.range(of: startMarker)?.lowerBound)
        let end = try XCTUnwrap(source.range(of: endMarker, range: start..<source.endIndex)?.lowerBound)

        return String(source[start..<end])
    }
}
