import XCTest
@testable import Ping

final class LocalSavePermissionContractTests: XCTestCase {
    func testSettingsExposeSenderControlledLocalSavePermission() throws {
        let settingsSource = try readFixture("SettingsScene.swift")
        let archiveSource = try readFixture("LocalArchive.swift")

        XCTAssertTrue(archiveSource.contains("allowRecipientsToSaveMyVideosKey"))
        XCTAssertTrue(archiveSource.contains("allowRecipientsToSaveMyVideos"))
        XCTAssertTrue(settingsSource.contains("@AppStorage(LocalArchive.allowRecipientsToSaveMyVideosKey)"))
        XCTAssertTrue(settingsSource.contains("상대가 내 영상 저장 가능"))
        XCTAssertTrue(settingsSource.contains("상대가 허용한 영상만"))
    }

    func testSendPayloadCarriesSenderLocalSavePermission() throws {
        let appDelegateSource = try readFixture("AppDelegate.swift")
        let messageServiceSource = try readFixture("MessageService.swift")

        XCTAssertTrue(messageServiceSource.contains("let allowsLocalSave: Bool"))
        XCTAssertTrue(messageServiceSource.contains("\"allows_local_save_value\": input.allowsLocalSave"))
        XCTAssertTrue(appDelegateSource.contains("allowsLocalSave: LocalArchive.allowRecipientsToSaveMyVideos"))
    }

    func testPlaybackAndHistoryRespectSenderLocalSavePermission() throws {
        let appDelegateSource = try readFixture("AppDelegate.swift")
        let historyViewModelSource = try readFixture("HistoryViewModel.swift")
        let messageRowSource = try readFixture("MessageRowView.swift")
        let roomTimelineSource = try readFixture("RoomTimelineView.swift")
        let inlinePlayerSource = try readFixture("InlinePlayerView.swift")
        let thumbnailSource = try readFixture("VideoThumbnailView.swift")

        XCTAssertTrue(appDelegateSource.contains("LocalArchive.saveReceivedEnabled && message.allowsLocalSave"))
        XCTAssertTrue(historyViewModelSource.contains("guard message.canBeSavedLocally(by: currentUid)"))
        XCTAssertTrue(messageRowSource.contains("let canSave: Bool"))
        XCTAssertTrue(messageRowSource.contains("if canSave"))
        XCTAssertTrue(roomTimelineSource.contains("canSave: v.canBeSavedLocally(by: myUid)"))
        XCTAssertTrue(inlinePlayerSource.contains("guard isMine || message.allowsLocalSave else { return nil }"))
        XCTAssertTrue(thumbnailSource.contains("guard isMine || message.allowsLocalSave else { return nil }"))
    }

    func testSupabaseMigrationPersistsAndReturnsLocalSavePermission() throws {
        let sql = try readFixture("20260524000100_sender_local_save_permission.sql")

        XCTAssertTrue(sql.contains("add column if not exists allows_local_save boolean not null default false"))
        XCTAssertTrue(sql.contains("allows_local_save_value boolean default false"))
        XCTAssertTrue(sql.contains("allows_local_save"))
        XCTAssertTrue(sql.contains("m.allows_local_save"))
    }

    @MainActor
    func testHistoryPlaybackCacheUsesApplicationCachesDirectoryInsteadOfDocumentsArchive() {
        let cacheURL = HistoryCacheService().localURL(roomId: "room-1", messageId: "message-1")
        let cachesRoot = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first!

        XCTAssertTrue(cacheURL.standardizedFileURL.path.hasPrefix(cachesRoot.standardizedFileURL.path))
        XCTAssertFalse(cacheURL.standardizedFileURL.path.contains("/Documents/Ping/cache"))
    }

    private func readFixture(_ relativePath: String) throws -> String {
        let fileName = URL(fileURLWithPath: relativePath).lastPathComponent
        let fileURL = try XCTUnwrap(Bundle(for: Self.self).resourceURL?.appendingPathComponent(fileName))

        return try String(contentsOf: fileURL, encoding: .utf8)
    }
}
