import XCTest

final class PingMobileOnboardingContractTests: XCTestCase {
    func testUnpairedScreenExplainsCompanionRoleAndDesktopInstallURL() throws {
        let source = try readProjectSource("PingMobile/DesktopInstallGuideView.swift")

        XCTAssertTrue(source.contains("Mac용 Ping의 iPhone companion"))
        XCTAssertTrue(source.contains("PingProductLinks.desktopInstallPage"))
        XCTAssertTrue(source.contains("PingProductLinks.desktopInstallPageText"))
        XCTAssertTrue(source.contains("Mac 설치 링크 복사"))
        XCTAssertTrue(source.contains("Mac으로 공유"))
        XCTAssertTrue(source.contains("Safari에서 보기"))
        XCTAssertTrue(source.contains("설치 끝났어요, QR 스캔"))
        XCTAssertTrue(source.contains("UIPasteboard.general.string"))
        XCTAssertTrue(source.contains("ShareLink(item:"))
        XCTAssertTrue(source.contains("Link(destination:"))
    }

    func testUnpairedContentViewDelegatesToFocusedGuideView() throws {
        let source = try readProjectSource("PingMobile/ContentView.swift")
        let unpaired = try extract(
            "private var unpairedView: some View",
            through: ".sheet(isPresented: $showScanner)",
            from: source
        )

        XCTAssertTrue(unpaired.contains("DesktopInstallGuideView"))
        XCTAssertFalse(unpaired.contains("Text(\"Mac과 연결하기\")"))
        XCTAssertFalse(unpaired.contains(".task { await PushRegistrar.shared.registerIfPossible() }"))
    }

    private func readProjectSource(_ relativePath: String) throws -> String {
        let testsDir = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
        let projectRoot = testsDir.deletingLastPathComponent()
        return try String(contentsOf: projectRoot.appendingPathComponent(relativePath), encoding: .utf8)
    }

    private func extract(_ start: String, through end: String, from contents: String) throws -> String {
        let startRange = try XCTUnwrap(contents.range(of: start))
        let tail = contents[startRange.lowerBound...]
        let endRange = try XCTUnwrap(tail.range(of: end))
        return String(tail[..<endRange.upperBound])
    }
}
