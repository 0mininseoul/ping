import XCTest

final class OnboardingInputContractTests: XCTestCase {
    func testOnboardingUsesDedicatedInputFieldComponent() throws {
        let source = try readSourceFile("Ping/UI/Setup/PairingView.swift")

        XCTAssertTrue(source.contains("onboardingTextField("))
        XCTAssertTrue(source.contains("inputFieldSurface(isFocused:"))
    }

    func testOnboardingInputFieldsAvoidNestedGlassLayersWhileEditing() throws {
        let source = try readSourceFile("Ping/UI/Setup/PairingView.swift")
        let component = try sourceSlice(
            in: source,
            from: "private func onboardingTextField",
            to: "private func inputFieldSurface"
        )
        let surface = try sourceSlice(
            in: source,
            from: "private func inputFieldSurface",
            to: "private func stepHeading"
        )

        XCTAssertTrue(source.contains("onboardingInputCard(isFocused:"))
        XCTAssertFalse(component.contains("GlassPanel {"))
        XCTAssertFalse(surface.contains(".shadow("))
    }

    func testOnboardingOffersCreateJoinAndSmallLaterActions() throws {
        let viewSource = try readSourceFile("Ping/UI/Setup/PairingView.swift")
        let viewModelSource = try readSourceFile("Ping/UI/Setup/PairingViewModel.swift")

        XCTAssertTrue(viewModelSource.contains("case connectionChoice"))
        XCTAssertTrue(viewModelSource.contains("case createRoom(name: String)"))
        XCTAssertTrue(viewModelSource.contains("case joinRoom(Room)"))
        XCTAssertTrue(viewModelSource.contains("case later"))
        XCTAssertTrue(viewModelSource.contains("var completionPayload: OnboardingCompletion?"))

        XCTAssertTrue(viewSource.contains("룸 생성하기"))
        XCTAssertTrue(viewSource.contains("룸 참여하기"))
        XCTAssertTrue(viewSource.contains("secondaryLaterButton"))
        XCTAssertTrue(viewSource.contains("나중에 하기"))
        XCTAssertFalse(viewSource.contains("첫 룸 만들기"))
        XCTAssertFalse(viewSource.contains("var onComplete: (String, String) -> Void"))
    }

    func testJoinSearchKeepsBootstrapUidExclusionDuringOnboarding() throws {
        let source = try readSourceFile("Ping/UI/Setup/PairingView.swift")

        XCTAssertTrue(source.contains("private let excludingUid: String?"))
        XCTAssertTrue(source.contains("roomSearchViewModel.updateExcludingUid(excludingUid ?? AppState.shared.currentUser?.id)"))
    }

    func testLaterActionDoesNotAutoOpenRoomManagerFromEmptyObserver() throws {
        let source = try readSourceFile("Ping/AppDelegate.swift")

        XCTAssertTrue(source.contains("opensRoomManagerWhenEmpty: Bool = true"))
        XCTAssertTrue(source.contains("opensRoomManagerWhenEmpty: completion.action != .later"))
        XCTAssertTrue(source.contains("if opensRoomManagerWhenEmpty, rooms.isEmpty, onboardingWindow == nil"))
    }

    func testDeferredRoomSetupPersistsAcrossLaunches() throws {
        let appDelegateSource = try readSourceFile("Ping/AppDelegate.swift")
        let preferenceSource = try readSourceFile("Ping/Core/UserPreferences.swift")

        XCTAssertTrue(preferenceSource.contains("roomSetupDeferred"))
        XCTAssertTrue(appDelegateSource.contains("startObservers(uid: uid, opensRoomManagerWhenEmpty: !roomSetupWasDeferred)"))
        XCTAssertTrue(appDelegateSource.contains("UserDefaults.standard.set(true, forKey: PingPreferenceKeys.roomSetupDeferred)"))
        XCTAssertTrue(appDelegateSource.contains("UserDefaults.standard.set(false, forKey: PingPreferenceKeys.roomSetupDeferred)"))
    }

    func testOnboardingCompletionPreventsDuplicateSubmissionAndShowsErrors() throws {
        let appDelegateSource = try readSourceFile("Ping/AppDelegate.swift")
        let viewSource = try readSourceFile("Ping/UI/Setup/PairingView.swift")
        let viewModelSource = try readSourceFile("Ping/UI/Setup/PairingViewModel.swift")

        XCTAssertTrue(viewModelSource.contains("@Published var isCompleting = false"))
        XCTAssertTrue(appDelegateSource.contains("guard !viewModel.isCompleting else { return }"))
        XCTAssertTrue(appDelegateSource.contains("viewModel.isCompleting = true"))
        XCTAssertTrue(appDelegateSource.contains("viewModel.isCompleting = false"))
        XCTAssertTrue(appDelegateSource.contains("viewModel.errorMessage = error.localizedDescription"))
        XCTAssertTrue(viewSource.contains(".disabled(viewModel.isCompleting)"))
        XCTAssertTrue(viewSource.contains("처리 중..."))
    }

    func testFirstRoomNameDoesNotUsePlaceholderCopy() throws {
        let source = try readSourceFile("Ping/UI/Setup/PairingView.swift")

        XCTAssertFalse(source.contains("예: \\(viewModel.trimmedNickname)"))
        XCTAssertTrue(source.contains("placeholder: \"\""))
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
