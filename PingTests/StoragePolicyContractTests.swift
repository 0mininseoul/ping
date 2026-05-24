import XCTest

final class StoragePolicyContractTests: XCTestCase {
    func testRoomMemberStorageReadPolicyAllowsSeenVideoMessages() throws {
        let baselinePolicy = try readSourceFile("20260523000500_storage_read_room_member.sql")
        let patchPolicy = try readSourceFile("20260524000200_storage_read_seen_messages.sql")

        for policy in [baselinePolicy, patchPolicy] {
            XCTAssertTrue(policy.contains("Ping videos room member read"))
            XCTAssertTrue(policy.contains("m.status in ('uploaded', 'seen')"))
            XCTAssertFalse(policy.contains("m.status = 'uploaded'"))
        }
    }

    private func readSourceFile(_ relativePath: String) throws -> String {
        let fileName = URL(fileURLWithPath: relativePath).lastPathComponent
        let fileURL = try XCTUnwrap(Bundle(for: Self.self).resourceURL?.appendingPathComponent(fileName))

        return try String(contentsOf: fileURL, encoding: .utf8)
    }
}
