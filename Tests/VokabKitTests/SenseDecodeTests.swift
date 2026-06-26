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

    func testLegacyEntrySynthesizesSingleSense() throws {
        let card = try JSONCleaning.decode(WordCard.self,
            from: #"{"pos":"noun","meaning":"con chó","examples":["a big dog"]}"#)
        XCTAssertEqual(card.senses.count, 0)            // raw senses absent
        let r = card.resolvedSenses
        XCTAssertEqual(r.count, 1)                      // one synthesized sense
        XCTAssertEqual(r[0].pos, "noun")
        XCTAssertEqual(r[0].meaning, "con chó")
        XCTAssertEqual(r[0].examples, ["a big dog"])
    }

    func testPrimarySenseMirrorsIntoTopLevel() throws {
        let json = #"{"senses":[{"pos":"noun","meaning":"lượt chạy","matches_context":true},{"pos":"verb","meaning":"chạy"}]}"#
        let card = try JSONCleaning.decode(WordCard.self, from: json)
        XCTAssertEqual(card.pos, "noun")                // matches_context sense mirrored up
        XCTAssertEqual(card.meaning, "lượt chạy")
        XCTAssertEqual(card.primarySense?.pos, "noun")
    }

    func testGlossPrefersMeaningLanguageThenEnglish() throws {
        var card = try JSONCleaning.decode(WordCard.self,
            from: #"{"senses":[{"pos":"verb","meaning":"chạy","meaning_en":"to run"}]}"#)
        card.meaningLang = "vi"
        let s = card.resolvedSenses[0]
        XCTAssertEqual(card.gloss(s, forLanguage: "vi"), "chạy")
        XCTAssertEqual(card.gloss(s, forLanguage: "en"), "to run")
    }

    func testCombinedPOSJoinsDistinctSenses() throws {
        let json = #"{"senses":[{"pos":"verb","meaning":"chạy"},{"pos":"noun","meaning":"lượt chạy"}]}"#
        let card = try JSONCleaning.decode(WordCard.self, from: json)
        XCTAssertEqual(card.combinedPOS, "verb / noun")
    }

    func testCombinedPOSDedupesAndFallsBackToLegacyPos() throws {
        let dup = try JSONCleaning.decode(WordCard.self,
            from: #"{"senses":[{"pos":"noun","meaning":"a"},{"pos":"Noun","meaning":"b"}]}"#)
        XCTAssertEqual(dup.combinedPOS, "noun")         // case-insensitive dedupe, first spelling kept
        let legacy = try JSONCleaning.decode(WordCard.self, from: #"{"pos":"adverb","meaning":"nhanh"}"#)
        XCTAssertEqual(legacy.combinedPOS, "adverb")    // legacy single-pos still works
    }
}
