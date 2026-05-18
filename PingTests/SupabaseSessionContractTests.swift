import XCTest

final class SupabaseSessionContractTests: XCTestCase {
    func testRefreshFailureDoesNotSilentlyCreateNewAnonymousUser() throws {
        let clientSource = try readSourceFile("Ping/Backend/SupabaseClient.swift")
        let errorSource = try readSourceFile("Ping/Core/PingError.swift")

        XCTAssertTrue(errorSource.contains("supabaseSessionExpired"))
        XCTAssertTrue(clientSource.contains("throw PingError.supabaseSessionExpired"))
        XCTAssertFalse(clientSource.contains("""
        clearSession()
                    let anonymousSession = try await signInAnonymously()
        """))
    }

    private func readSourceFile(_ relativePath: String) throws -> String {
        let fileName = URL(fileURLWithPath: relativePath).lastPathComponent
        let fileURL = try XCTUnwrap(Bundle(for: Self.self).resourceURL?.appendingPathComponent(fileName))

        return try String(contentsOf: fileURL, encoding: .utf8)
    }
}
