import XCTest
@testable import VokabKit

final class SenseDecodeTests: XCTestCase {
    func testDecodesMultipleSenses() throws {
        let json = #"""
        {"ipa":"rʌn","senses":[
          {"pos":"verb","meaning":"chạy","meaning_en":"move fast on foot","examples":["I run every morning"],"matches_context":true},
          {"pos":"noun","meaning":"lượt chạy","meaning_en":"an act of running","examples":["a 5km run"],"matches_context":false}
        ]}
        """#
        let card = try JSONCleaning.decode(WordCard.self, from: json)
        XCTAssertEqual(card.senses.count, 2)
        XCTAssertEqual(card.senses[0].pos, "verb")
        XCTAssertEqual(card.senses[0].meaning, "chạy")
        XCTAssertEqual(card.senses[0].meaningEn, "move fast on foot")
        XCTAssertEqual(card.senses[0].examples, ["I run every morning"])
        XCTAssertTrue(card.senses[0].matchesContext)
        XCTAssertEqual(card.senses[1].pos, "noun")
        XCTAssertFalse(card.senses[1].matchesContext)
    }
}
