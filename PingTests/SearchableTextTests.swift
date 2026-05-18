import XCTest
@testable import Ping

final class SearchableTextTests: XCTestCase {
    func testNormalizeLowercasesAndRemovesSpaces() {
        XCTAssertEqual(SearchableText.normalize("박영민 ↔ 파트너"), "박영민↔파트너")
        XCTAssertEqual(SearchableText.normalize("Hello World"), "helloworld")
        XCTAssertEqual(SearchableText.normalize("  사 용 자  "), "사용자")
    }

    func testMatchesPrefixCaseAndSpaceInsensitive() {
        XCTAssertTrue(SearchableText.matchesPrefix(target: "박영민파트너", query: "박영민"))
        XCTAssertTrue(SearchableText.matchesPrefix(target: "박영민파트너", query: "박 영 민"))
        XCTAssertTrue(SearchableText.matchesPrefix(target: "박영민파트너", query: ""))
        XCTAssertFalse(SearchableText.matchesPrefix(target: "박영민", query: "파트너"))
    }
}
