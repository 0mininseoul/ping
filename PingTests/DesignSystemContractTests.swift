import XCTest

final class DesignSystemContractTests: XCTestCase {
    func testGlassButtonOwnsSharedHoverMotion() throws {
        let source = try readSourceFile("Ping/UI/Glass/GlassButton.swift")

        XCTAssertTrue(source.contains("@State private var isHovering"))
        XCTAssertTrue(source.contains(".onHover"))
        XCTAssertTrue(source.contains("PingDesign.Motion.buttonHover"))
    }

    func testGlassButtonUsesStableSurfacesInsteadOfGlassSampling() throws {
        let source = try readSourceFile("Ping/UI/Glass/GlassButton.swift")

        XCTAssertFalse(source.contains(".glassEffect()"))
        XCTAssertTrue(source.contains("stableSecondaryFill"))
    }

    func testGlassEffectIsIsolatedBehindCompatibilityModifier() throws {
        let glassCompat = try readSourceFile("Ping/UI/Glass/GlassEffectCompat.swift")
        let glassChip = try readSourceFile("Ping/UI/Glass/GlassChip.swift")
        let partnerPicker = try readSourceFile("Ping/UI/Mirror/PartnerPicker.swift")
        let mirrorView = try readSourceFile("Ping/UI/Mirror/MirrorView.swift")

        XCTAssertTrue(glassCompat.contains("if #available(macOS 26.0, *)"))
        XCTAssertTrue(glassCompat.contains(".glassEffect()"))
        XCTAssertTrue(glassCompat.contains("macOS 26"))
        XCTAssertTrue(glassCompat.contains("pre-Tahoe"))
        XCTAssertFalse(glassChip.contains(".glassEffect()"))
        XCTAssertFalse(partnerPicker.contains(".glassEffect()"))
        XCTAssertFalse(mirrorView.contains(".glassEffect()"))
        XCTAssertTrue(glassChip.contains(".pingGlassEffect()"))
        XCTAssertTrue(partnerPicker.contains(".pingGlassEffect()"))
        XCTAssertTrue(mirrorView.contains(".pingGlassEffect()"))
    }

    func testLightModeRoomSurfacesAvoidNestedGlassLayers() throws {
        let source = try readSourceFile("Ping/UI/Setup/RoomListView.swift")
        let roomCard = try sourceSlice(
            in: source,
            from: "private func roomCard",
            to: "private func statusBadge"
        )
        let statusBadge = try sourceSlice(
            in: source,
            from: "private func statusBadge",
            to: "private func partnerSummary"
        )

        XCTAssertFalse(roomCard.contains("GlassPanel"))
        XCTAssertFalse(roomCard.contains(".glassEffect()"))
        XCTAssertFalse(statusBadge.contains(".glassEffect()"))
        XCTAssertTrue(roomCard.contains("roomCardBackground"))
    }

    func testRoomSearchSurfacesAvoidGlassSamplingInLightMode() throws {
        let source = try readSourceFile("Ping/UI/Setup/RoomSearchView.swift")
        let searchField = try sourceSlice(
            in: source,
            from: "private var searchField",
            to: "private var tabPicker"
        )

        XCTAssertFalse(searchField.contains("GlassPanel"))
        XCTAssertFalse(searchField.contains(".glassEffect()"))
        XCTAssertTrue(source.contains("searchSurface"))
    }

    func testGeneralSettingsUsesCustomGroupedLayout() throws {
        let source = try readSourceFile("Ping/UI/Setup/SettingsScene.swift")
        let general = try sourceSlice(
            in: source,
            from: "private struct GeneralSettingsView",
            to: "private struct HotkeySettingsView"
        )

        XCTAssertFalse(general.contains("Form {"))
        XCTAssertTrue(general.contains("settingsGroup"))
        XCTAssertTrue(general.contains("settingRow"))
    }

    func testOnboardingHeaderUsesDedicatedWordmarkFont() throws {
        let source = try readSourceFile("Ping/UI/Setup/PairingView.swift")

        XCTAssertTrue(source.contains(".font(PingFont.wordmark)"))
    }

    func testDesignSystemDocumentsOklchAndShadowFactory() throws {
        let tokenSource = try readSourceFile("Ping/UI/Glass/PingDesign.swift")
        let designDoc = try readSourceFile("docs/DESIGN_SYSTEM.md")

        XCTAssertTrue(tokenSource.contains("OKLCH source"))
        XCTAssertTrue(tokenSource.contains("static func colored("))
        XCTAssertTrue(tokenSource.contains("inputCardFill"))
        XCTAssertTrue(tokenSource.contains("inputFieldFill"))
        XCTAssertTrue(designDoc.contains("OKLCH"))
        XCTAssertTrue(designDoc.contains("layered colored shadow"))
    }

    func testMirrorShadowIsDrawnFromCircularSurface() throws {
        let source = try readSourceFile("Ping/UI/Mirror/MirrorView.swift")
        let body = try sourceSlice(
            in: source,
            from: "var body: some View",
            to: "@ViewBuilder private var topOverlay"
        )
        let shadowSurface = try sourceSlice(
            in: source,
            from: "private var mirrorShadowSurface",
            to: "private var mirrorContent"
        )

        XCTAssertTrue(body.contains("mirrorShadowSurface"))
        XCTAssertTrue(body.contains("mirrorContent"))
        XCTAssertFalse(body.contains(".frame(width: 200, height: 200)\n        .pingShadow"))
        // Shadow surface uses mode-aware mirrorShape (Circle for faceOnly, RoundedRectangle for screenFace)
        XCTAssertTrue(shadowSurface.contains("mirrorShape"))
        XCTAssertTrue(shadowSurface.contains(".pingShadow(PingDesign.Shadow.mirror)"))
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
