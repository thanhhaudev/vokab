import XCTest
@testable import VokabKit

final class SpellIssueKindTests: XCTestCase {
    func testSuggestionMeansTypo() {
        XCTAssertEqual(SpellIssueKind.classify(word: "recieve", hasSuggestion: true), .typo)
    }
    func testNoSuggestionGibberishIsNonexistent() {
        XCTAssertEqual(SpellIssueKind.classify(word: "asdfgh", hasSuggestion: false), .nonexistent)
    }
    func testNoSuggestionButWordShapedIsUnknown() {
        XCTAssertEqual(SpellIssueKind.classify(word: "Nginx", hasSuggestion: false), .unknown)
    }
}
