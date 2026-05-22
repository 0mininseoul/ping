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

        XCTAssertTrue(clientSource.contains("applicationSupportDirectory"))
        XCTAssertTrue(clientSource.contains("loadLegacyDefaultsSession"))
        XCTAssertTrue(clientSource.contains("saveFileData(data)"))
        XCTAssertTrue(clientSource.contains("UserDefaults.standard.set(data, forKey: defaultsKey)"))
    }

    func testSupabaseSessionAvoidsAutomaticKeychainAccess() throws {
        let clientSource = try readSourceFile("Ping/Backend/SupabaseClient.swift")

        XCTAssertTrue(clientSource.contains("loadFileSession() ?? loadLegacyDefaultsSession()"))
        XCTAssertTrue(clientSource.contains("savePortableCopy(session)"))
        XCTAssertFalse(clientSource.contains("import Security"))
        XCTAssertFalse(clientSource.contains("import LocalAuthentication"))
        XCTAssertFalse(clientSource.contains("SecItemCopyMatching"))
        XCTAssertFalse(clientSource.contains("SecItemAdd"))
        XCTAssertFalse(clientSource.contains("SecItemUpdate"))
        XCTAssertFalse(clientSource.contains("SecItemDelete"))
        XCTAssertFalse(clientSource.contains("saveKeychainData"))
        XCTAssertFalse(clientSource.contains("loadKeychainSession"))
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
