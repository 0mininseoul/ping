import XCTest
@testable import Ping

final class OnboardingCopyTests: XCTestCase {
    func testWelcomeCopyMatchesProductPositioning() {
        XCTAssertEqual(OnboardingCopy.welcomeHeadline, "보고 싶을 때 바로 Ping")
        XCTAssertEqual(OnboardingCopy.welcomeSubtitle, "Option+P로 거울을 열고, Enter로 3초를 보냅니다.")
    }
}
