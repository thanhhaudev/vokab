import XCTest
@testable import VokabKit

final class CardMergeTests: XCTestCase {
    func testWordMergeFillsEmptyFromEnrichment() throws {
        let core = try JSONCleaning.decode(WordCard.self, from: #"{"pos":"noun","meaning_vi":"x","synonyms":[]}"#)
        let enrich = try JSONCleaning.decode(WordCard.self, from: #"{"etymology":"Greek","synonyms":["a","b"],"pos":"VERB"}"#)
        let m = core.merging(enrich)
        XCTAssertEqual(m.pos, "noun")            // core wins when present
        XCTAssertEqual(m.etymology, "Greek")      // enrich fills nil
        XCTAssertEqual(m.synonyms, ["a", "b"])    // enrich fills empty array
    }

    func testPhraseMergeKeepsCoreScalars() throws {
        let core = try JSONCleaning.decode(PhraseCard.self, from: #"{"meaning_vi":"y","variations":[]}"#)
        let enrich = try JSONCleaning.decode(PhraseCard.self, from: #"{"usage_note":"note","variations":["v1"],"separable":true}"#)
        let m = core.merging(enrich)
        XCTAssertEqual(m.meaningVi, "y")
        XCTAssertEqual(m.usageNote, "note")
        XCTAssertEqual(m.variations, ["v1"])
        XCTAssertEqual(m.separable, true)
    }

    func testMergingKeepsCoreCategory() throws {
        let core = try JSONCleaning.decode(WordCard.self, from: #"{"category":"Technology"}"#)
        let enrich = try JSONCleaning.decode(WordCard.self, from: #"{"category":"Science","synonyms":["a"]}"#)
        XCTAssertEqual(core.merging(enrich).category, "Technology")  // core wins
    }

    func testMergingFillsMissingCategory() throws {
        let core = try JSONCleaning.decode(WordCard.self, from: #"{"synonyms":["a"]}"#)
        let other = try JSONCleaning.decode(WordCard.self, from: #"{"category":"Science"}"#)
        XCTAssertEqual(core.merging(other).category, "Science")
    }
}
