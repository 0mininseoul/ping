import XCTest
@testable import Ping

final class SearchableTextTests: XCTestCase {
    func testNormalizeLowercasesAndRemovesSpaces() {
        XCTAssertEqual(SearchableText.normalize("박영민 ↔ 김나영"), "박영민↔김나영")
        XCTAssertEqual(SearchableText.normalize("Hello World"), "helloworld")
        XCTAssertEqual(SearchableText.normalize("  김 나 영  "), "김나영")
    }

    func testMatchesPrefixCaseAndSpaceInsensitive() {
        XCTAssertTrue(SearchableText.matchesPrefix(target: "박영민김나영", query: "박영민"))
        XCTAssertTrue(SearchableText.matchesPrefix(target: "박영민김나영", query: "박 영 민"))
        XCTAssertTrue(SearchableText.matchesPrefix(target: "박영민김나영", query: ""))
        XCTAssertFalse(SearchableText.matchesPrefix(target: "박영민", query: "김"))
    }
}
