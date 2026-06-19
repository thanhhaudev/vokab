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

    func testWordMergingFillsContextOfUseAndGrammarNoteFromOther() throws {
        let base = try JSONCleaning.decode(WordCard.self, from: #"{"meaning_vi":"x"}"#)
        let other = try JSONCleaning.decode(WordCard.self, from: #"""
            {"context_of_use":"Dùng trong văn trang trọng.","grammar_note":"Thường dùng thì hiện tại hoàn thành."}
        """#)
        let merged = base.merging(other)
        XCTAssertEqual(merged.contextOfUse, "Dùng trong văn trang trọng.")
        XCTAssertEqual(merged.grammarNote, "Thường dùng thì hiện tại hoàn thành.")
    }

    func testWordMergingKeepsSelfContextOfUseAndGrammarNote() throws {
        let base = try JSONCleaning.decode(WordCard.self, from: #"""
            {"context_of_use":"Giữ giá trị gốc.","grammar_note":"Ghi chú gốc."}
        """#)
        let other = try JSONCleaning.decode(WordCard.self, from: #"""
            {"context_of_use":"Giá trị khác.","grammar_note":"Ghi chú khác."}
        """#)
        let merged = base.merging(other)
        XCTAssertEqual(merged.contextOfUse, "Giữ giá trị gốc.")
        XCTAssertEqual(merged.grammarNote, "Ghi chú gốc.")
    }

    func testPhraseMergingFillsContextOfUseAndGrammarNoteFromOther() throws {
        let base = try JSONCleaning.decode(PhraseCard.self, from: #"{"meaning_vi":"y"}"#)
        let other = try JSONCleaning.decode(PhraseCard.self, from: #"""
            {"context_of_use":"Dùng trong giao tiếp thường ngày.","grammar_note":"Theo sau V-ing."}
        """#)
        let merged = base.merging(other)
        XCTAssertEqual(merged.contextOfUse, "Dùng trong giao tiếp thường ngày.")
        XCTAssertEqual(merged.grammarNote, "Theo sau V-ing.")
    }

    func testPhraseMergingKeepsSelfContextOfUseAndGrammarNote() throws {
        let base = try JSONCleaning.decode(PhraseCard.self, from: #"""
            {"context_of_use":"Bối cảnh gốc.","grammar_note":"Ngữ pháp gốc."}
        """#)
        let other = try JSONCleaning.decode(PhraseCard.self, from: #"""
            {"context_of_use":"Bối cảnh khác.","grammar_note":"Ngữ pháp khác."}
        """#)
        let merged = base.merging(other)
        XCTAssertEqual(merged.contextOfUse, "Bối cảnh gốc.")
        XCTAssertEqual(merged.grammarNote, "Ngữ pháp gốc.")
    }
}
