import XCTest

final class CompatibilityContractTests: XCTestCase {
    func testProjectTargetsMacOS13AndSwift6() throws {
        let project = try readFixture("project.yml")
        let info = try readFixture("Ping/Info.plist")

        XCTAssertTrue(project.contains("macOS: \"13.0\""))
        XCTAssertTrue(project.contains("MACOSX_DEPLOYMENT_TARGET: \"13.0\""))
        XCTAssertEqual(project.countOccurrences(of: "deploymentTarget: \"13.0\""), 2)
        XCTAssertTrue(project.contains("SWIFT_VERSION: \"6.0\""))
        XCTAssertTrue(info.contains("<key>LSMinimumSystemVersion</key>"))
        XCTAssertTrue(info.contains("<string>13.0</string>"))
    }

    func testDocsDescribeMacOS13CompatibilityInsteadOfMacOS26Only() throws {
        let spec = try readFixture("PING_PROJECT_SPECIFICATION.md")
        let readme = try readFixture("README.md")
        let agents = try readFixture("AGENTS.md")

        for document in [spec, readme, agents] {
            XCTAssertTrue(document.contains("macOS 13 Ventura 이상"))
            XCTAssertFalse(document.contains("macOS 26 Tahoe 전용"))
            XCTAssertFalse(document.contains("macOS 26 Tahoe 이상"))
            XCTAssertFalse(document.contains("macOS 26을 최저"))
            XCTAssertFalse(document.contains("`macOS: \"26.0\"`"))
            XCTAssertFalse(document.contains("`macOS 14` / `15` 로 deploymentTarget 낮추지 말 것"))
        }
    }

    func testAppSwiftSourcesUseGlassEffectOnlyThroughCompatibilityWrapper() throws {
        let repositoryRoot = try repositoryRoot()
        let appSourceRoot = repositoryRoot.appendingPathComponent("Ping")
        let allowedRelativePath = "Ping/UI/Glass/GlassEffectCompat.swift"
        let swiftSources = try swiftSourceFiles(under: appSourceRoot)

        XCTAssertFalse(swiftSources.isEmpty)

        let offenders = try swiftSources.compactMap { sourceURL -> String? in
            let contents = try String(contentsOf: sourceURL, encoding: .utf8)
            let relativePath = sourceURL.path.replacingOccurrences(of: repositoryRoot.path + "/", with: "")

            guard relativePath != allowedRelativePath, contents.contains(".glassEffect(") else {
                return nil
            }

            return relativePath
        }

        XCTAssertTrue(
            offenders.isEmpty,
            "Direct .glassEffect() is only allowed in \(allowedRelativePath). Offenders: \(offenders.joined(separator: ", "))"
        )
    }

    private func readFixture(_ relativePath: String) throws -> String {
        let fileName = URL(fileURLWithPath: relativePath).lastPathComponent
        let fileURL = try XCTUnwrap(Bundle(for: Self.self).resourceURL?.appendingPathComponent(fileName))

        return try String(contentsOf: fileURL, encoding: .utf8)
    }

    private func repositoryRoot() throws -> URL {
        let testFile = URL(fileURLWithPath: #filePath)
        let root = testFile.deletingLastPathComponent().deletingLastPathComponent()

        XCTAssertTrue(
            FileManager.default.fileExists(atPath: root.appendingPathComponent("Ping").path),
            "Expected to derive repository root from #filePath"
        )

        return root
    }

    private func swiftSourceFiles(under root: URL) throws -> [URL] {
        let enumerator = try XCTUnwrap(
            FileManager.default.enumerator(
                at: root,
                includingPropertiesForKeys: [.isRegularFileKey],
                options: [.skipsHiddenFiles]
            )
        )

        return try enumerator.compactMap { item -> URL? in
            guard let url = item as? URL, url.pathExtension == "swift" else {
                return nil
            }

            let resourceValues = try url.resourceValues(forKeys: [.isRegularFileKey])
            return resourceValues.isRegularFile == true ? url : nil
        }
    }
}

private extension String {
    func countOccurrences(of needle: String) -> Int {
        components(separatedBy: needle).count - 1
    }
}
