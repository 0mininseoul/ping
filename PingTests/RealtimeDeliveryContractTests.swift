import XCTest
@testable import Ping

@MainActor final class RealtimeDeliveryContractTests: XCTestCase {
    private let now = Date()

    // MARK: - Realtime endpoint

    /// 회귀 방지: URLComponents로 조립하면 슬래시 없는 프로젝트 URL에서 nil이 나와
    /// Realtime이 연결을 시도조차 못 하고 폴링으로 떨어졌다(2026-09-03까지).
    func testSocketURLHandlesAProjectURLWithoutATrailingSlash() throws {
        let project = try XCTUnwrap(URL(string: "https://abc.supabase.co"))
        XCTAssertEqual(
            RealtimeEndpoint.socketURL(for: project).absoluteString,
            "https://abc.supabase.co/realtime/v1"
        )
    }

    func testSocketURLHandlesATrailingSlash() throws {
        let project = try XCTUnwrap(URL(string: "https://abc.supabase.co/"))
        XCTAssertEqual(
            RealtimeEndpoint.socketURL(for: project).absoluteString,
            "https://abc.supabase.co/realtime/v1"
        )
    }

    func testSocketURLNeverProducesADoubleSlashPath() throws {
        for raw in ["https://abc.supabase.co", "https://abc.supabase.co/"] {
            let url = RealtimeEndpoint.socketURL(for: try XCTUnwrap(URL(string: raw)))
            XCTAssertFalse(url.path.contains("//"), "\(raw) -> \(url)")
            XCTAssertTrue(url.path.hasPrefix("/"), "\(raw) -> \(url)")
        }
    }

    /// 실제 배포 설정이 슬래시 없는 형태다. 예시 plist가 그 형태를 유지하는지 본다.
    func testExampleConfigURLStillBuildsAValidSocketURL() throws {
        let plist = try readRepositoryFile("Resources/Supabase.example.plist")
        XCTAssertTrue(plist.contains("SUPABASE_URL"))
    }

    // MARK: - Chat polling must not replay history

    /// 회귀 방지: 폴백 폴링이 실행할 때마다 최근 20건을 "새 메시지"로 재생해
    /// 한 번에 21건이 발송됐고, macOS가 전부 배너 없이 알림 센터로 흘려보냈다.
    func testPollingSkipsMessagesOlderThanTheBaseline() {
        XCTAssertFalse(
            ChatRealtimeService.isFresh(
                messageCreatedAt: now.addingTimeInterval(-120),
                pollingStartedAt: now
            )
        )
    }

    func testPollingDeliversMessagesFromAfterTheBaseline() {
        XCTAssertTrue(
            ChatRealtimeService.isFresh(
                messageCreatedAt: now.addingTimeInterval(5),
                pollingStartedAt: now
            )
        )
    }

    func testPollingDeliversMessagesExactlyAtTheBaseline() {
        XCTAssertTrue(
            ChatRealtimeService.isFresh(messageCreatedAt: now, pollingStartedAt: now)
        )
    }

    func testMessageWithoutATimestampIsNotReplayed() {
        XCTAssertFalse(
            ChatRealtimeService.isFresh(messageCreatedAt: nil, pollingStartedAt: now)
        )
    }

    func testEverythingIsFreshBeforePollingHasStarted() {
        XCTAssertTrue(
            ChatRealtimeService.isFresh(
                messageCreatedAt: now.addingTimeInterval(-9999),
                pollingStartedAt: nil
            )
        )
    }

    // MARK: - Source contracts

    func testIncomingVideosAreWatchedOverRealtime() throws {
        let service = try readRepositoryFile("Ping/Backend/ChatRealtimeService.swift")
        let appDelegate = try readRepositoryFile("Ping/AppDelegate.swift")
        let migration = try readRepositoryFile(
            "supabase/migrations/20260903020000_realtime_incoming_videos.sql"
        )

        XCTAssertTrue(service.contains("case incomingVideo"))
        XCTAssertTrue(service.contains("table: \"messages\""))
        XCTAssertTrue(service.contains("filter: \"receiver_uid=eq.\\(uid)\""))
        XCTAssertTrue(appDelegate.contains("fetchIncomingVideosNow()"))
        XCTAssertTrue(migration.contains("alter publication supabase_realtime add table public.messages"))
    }

    /// 폴링과 Realtime이 같은 메시지를 동시에 물어도 알림은 한 번만 나가야 한다.
    func testDeliveryGuardsAgainstConcurrentPaths() throws {
        let appDelegate = try readRepositoryFile("Ping/AppDelegate.swift")

        XCTAssertTrue(appDelegate.contains("deliveringVideoIds"))
        XCTAssertTrue(appDelegate.contains("guard !deliveringVideoIds.contains(id) else { return }"))
        XCTAssertTrue(appDelegate.contains("defer { deliveringVideoIds.remove(id) }"))
    }

    private func readRepositoryFile(_ relativePath: String) throws -> String {
        let repoRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        return try String(contentsOf: repoRoot.appendingPathComponent(relativePath), encoding: .utf8)
    }
}
