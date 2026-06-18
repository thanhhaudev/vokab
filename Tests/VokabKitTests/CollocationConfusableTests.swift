import XCTest
@testable import VokabKit

final class CollocationConfusableTests: XCTestCase {
    private func decode(_ json: String) throws -> WordCard {
        try JSONCleaning.decode(WordCard.self, from: json)
    }

    func testDecodesCollocationsAndConfusables() throws {
        let json = #"""
        {"meaning_vi":"ảnh hưởng","collocations":["make a decision","take a decision"],
         "confusables":[{"word":"effect","note_vi":"effect là danh từ (kết quả)"}]}
        """#
        let card = try decode(json)
        XCTAssertEqual(card.collocations, ["make a decision", "take a decision"])
        XCTAssertEqual(card.confusables.count, 1)
        XCTAssertEqual(card.confusables.first?.word, "effect")
        XCTAssertEqual(card.confusables.first?.noteVi, "effect là danh từ (kết quả)")
    }

    func testMissingFieldsDefaultToEmpty() throws {
        let card = try decode(#"{"meaning_vi":"x"}"#)
        XCTAssertTrue(card.collocations.isEmpty)
        XCTAssertTrue(card.confusables.isEmpty)
    }

    func testConfusableWithoutWordIsDropped() throws {
        let json = #"{"confusables":[{"note_vi":"orphan note"},{"word":"effect"}]}"#
        let card = try decode(json)
        XCTAssertEqual(card.confusables.map(\.word), ["effect"])
    }

    func testMergingFillsWhenEmptyAndPreservesWhenPresent() throws {
        let base = try decode(#"{"collocations":["keep this"],"confusables":[{"word":"keep"}]}"#)
        let other = try decode(#"{"collocations":["new"],"confusables":[{"word":"new"}]}"#)
        let merged = base.merging(other)
        XCTAssertEqual(merged.collocations, ["keep this"])
        XCTAssertEqual(merged.confusables.map(\.word), ["keep"])

        let empty = try decode("{}")
        let filled = empty.merging(other)
        XCTAssertEqual(filled.collocations, ["new"])
        XCTAssertEqual(filled.confusables.map(\.word), ["new"])
    }
}
