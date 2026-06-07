import XCTest

final class PingMobileOnboardingContractTests: XCTestCase {
    func testUnpairedScreenExplainsCompanionRoleAndDesktopInstallURL() throws {
        let source = try readProjectSource("PingMobile/DesktopInstallGuideView.swift")

        XCTAssertTrue(source.contains("Mac용 Ping과 연결해서 사용하는\\niPhone 컴패니언 앱이에요"))
        XCTAssertTrue(source.contains("Mac 앱을 설치한 뒤, QR 코드를 열고 스캔하세요"))
        XCTAssertTrue(source.contains("Mac 앱 설치 페이지"))
        XCTAssertTrue(source.contains("PingProductLinks.desktopInstallPage"))
        XCTAssertTrue(source.contains("PingProductLinks.desktopInstallPageText"))
        XCTAssertTrue(source.contains("QR 스캔"))
        XCTAssertTrue(source.contains("UIPasteboard.general.string"))
        XCTAssertTrue(source.contains("ShareLink(item:"))
        XCTAssertTrue(source.contains("Link(destination:"))
        XCTAssertFalse(source.contains("Mac 설치 링크 복사"))
        XCTAssertFalse(source.contains("Mac으로 공유"))
        XCTAssertFalse(source.contains("Safari에서 보기"))
        XCTAssertFalse(source.contains("설치 끝났어요, QR 스캔"))
        XCTAssertFalse(source.contains("앱 기능 미리보기"))
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
        XCTAssertFalse(unpaired.contains("onPreview"))
    }

    func testQRScannerSheetUsesOnlySystemDragIndicator() throws {
        let source = try readProjectSource("PingMobile/ContentView.swift")
        let scannerSheet = try extract(
            ".sheet(isPresented: $showScanner)",
            through: "private func handleScanned",
            from: source
        )

        XCTAssertTrue(scannerSheet.contains(".presentationDragIndicator(.visible)"))
        XCTAssertFalse(scannerSheet.contains("chevron.down"))
        XCTAssertFalse(scannerSheet.contains("xmark"))
    }

    func testPairedInboxDoesNotShowConnectedEmptyStateDuringInitialRoomLoad() throws {
        let source = try readProjectSource("PingMobile/InboxView.swift")
        let body = try extract(
            "var body: some View",
            through: ".refreshable",
            from: source
        )

        XCTAssertTrue(body.contains("if isLoading && rooms.isEmpty"))
        XCTAssertTrue(source.contains("private var loadingState: some View"))
        let loadingRange = try XCTUnwrap(body.range(of: "if isLoading && rooms.isEmpty"))
        let emptyRange = try XCTUnwrap(body.range(of: "else if rooms.isEmpty"))
        XCTAssertLessThan(loadingRange.lowerBound, emptyRange.lowerBound)
        XCTAssertFalse(body.contains("if isLoading && rooms.isEmpty { ProgressView() }"))
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
