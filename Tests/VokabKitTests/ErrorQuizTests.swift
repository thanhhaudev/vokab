import XCTest
@testable import VokabKit

final class ErrorQuizTests: XCTestCase {
    private func phrase(_ json: String) throws -> PhraseCard { try JSONCleaning.decode(PhraseCard.self, from: json) }

    func testDecodesStructuredCommonErrors() throws {
        let json = #"""
        {"common_errors":[{"sentence":"Don't give up _____ me.","answer":"on",
          "options":["on","to","at"],"note_vi":"give up + on + sb"}]}
        """#
        let card = try phrase(json)
        XCTAssertEqual(card.commonErrors.count, 1)
        XCTAssertEqual(card.commonErrors.first?.answer, "on")
        XCTAssertEqual(card.commonErrors.first?.options, ["on","to","at"])
        XCTAssertEqual(card.commonErrors.first?.noteVi, "give up + on + sb")
        XCTAssertTrue(card.commonErrors.first!.sentence.contains("_____"))
    }
    func testDropsItemMissingAnswerOrSentence() throws {
        let json = #"{"common_errors":[{"sentence":"x _____","options":["a"]},{"answer":"on"},{"sentence":"y _____","answer":"on","options":["on"]}]}"#
        XCTAssertEqual(try phrase(json).commonErrors.count, 1)
    }
    func testOldStringArrayMigratesToEmpty() throws {
        let card = try phrase(#"{"common_errors":["give up to"]}"#)
        XCTAssertTrue(card.commonErrors.isEmpty)
    }
    func testMergingFillsWhenEmpty() throws {
        let base = try phrase("{}")
        let other = try phrase(#"{"common_errors":[{"sentence":"a _____","answer":"on","options":["on"]}]}"#)
        XCTAssertEqual(base.merging(other).commonErrors.count, 1)
        XCTAssertEqual(other.merging(base).commonErrors.count, 1)
    }
}
