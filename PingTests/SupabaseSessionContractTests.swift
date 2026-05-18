import XCTest

final class SupabaseSessionContractTests: XCTestCase {
    func testAnonymousAuthSessionCreationIsSerialized() throws {
        let clientSource = try readSourceFile("Ping/Backend/SupabaseClient.swift")

        XCTAssertTrue(clientSource.contains("private var authSessionTask: Task<SupabaseSession, Error>?"))
        XCTAssertTrue(clientSource.contains("if let authSessionTask"))
        XCTAssertTrue(clientSource.contains("let task = Task { @MainActor in"))
        XCTAssertTrue(clientSource.contains("let authenticated = try await self.resolveAuthenticatedSession()"))
        XCTAssertTrue(clientSource.contains("self.save(session: authenticated)"))
    }

    func testSupabaseSessionPersistsOutsideLegacyUserDefaults() throws {
        let clientSource = try readSourceFile("Ping/Backend/SupabaseClient.swift")

        XCTAssertTrue(clientSource.contains("import Security"))
        XCTAssertTrue(clientSource.contains("SecItemCopyMatching"))
        XCTAssertTrue(clientSource.contains("SecItemAdd"))
        XCTAssertTrue(clientSource.contains("applicationSupportDirectory"))
        XCTAssertTrue(clientSource.contains("loadLegacyDefaultsSession"))
    }

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
