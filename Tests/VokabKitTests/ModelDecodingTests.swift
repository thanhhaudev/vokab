import XCTest
@testable import VokabKit

final class ModelDecodingTests: XCTestCase {

    func testDecodeWordCard() throws {
        let json = """
        {
          "ipa": "/ɪˈfɛmərəl/",
          "pos": "adjective",
          "meaning_vi": "phù du, chóng tàn",
          "meaning_en": "lasting a very short time",
          "examples": ["an ephemeral trend"],
          "etymology": "from Greek ephēmeros",
          "cefr_level": "C1",
          "register": "formal",
          "frequency": "low",
          "synonyms": ["transient", "fleeting"],
          "antonyms": ["permanent"],
          "word_family": ["ephemerality"]
        }
        """
        let card = try JSONCleaning.decode(WordCard.self, from: json)
        XCTAssertEqual(card.pos, "adjective")
        XCTAssertEqual(card.meaningVi, "phù du, chóng tàn")
        XCTAssertEqual(card.meaningEn, "lasting a very short time")
        XCTAssertEqual(card.cefrLevel, "C1")
        XCTAssertEqual(card.synonyms, ["transient", "fleeting"])
        XCTAssertEqual(card.wordFamily, ["ephemerality"])
    }

    func testDecodeWordCardWithMissingOptionalKeys() throws {
        // agy nondeterminism: only some keys present. Must not throw.
        let json = #"{"meaning_vi":"nghĩa","pos":"noun"}"#
        let card = try JSONCleaning.decode(WordCard.self, from: json)
        XCTAssertEqual(card.pos, "noun")
        XCTAssertEqual(card.meaningVi, "nghĩa")
        XCTAssertNil(card.ipa)
        XCTAssertEqual(card.examples, [])         // arrays default to empty
        XCTAssertEqual(card.synonyms, [])
    }

    func testDecodePhraseCard() throws {
        let json = """
        {
          "type": "phrasal_verb",
          "formula_pattern": "give up + on + sb/sth",
          "pattern_confidence": 0.92,
          "meaning_vi": "từ bỏ",
          "meaning_en": "stop trying",
          "register": "neutral",
          "cefr_level": "B1",
          "separable": true,
          "object_type": "noun phrase",
          "usage_note": "informal",
          "examples": ["Don't give up on me"],
          "variations": ["give up"],
          "common_errors": [{"sentence":"Don't give up _____ me.","answer":"on","options":["on","to"],"note_vi":"give up + on"}],
          "related_phrases": ["throw in the towel"]
        }
        """
        let card = try JSONCleaning.decode(PhraseCard.self, from: json)
        XCTAssertEqual(card.formulaPattern, "give up + on + sb/sth")
        XCTAssertEqual(card.patternConfidence, 0.92)
        XCTAssertEqual(card.separable, true)
        XCTAssertEqual(card.commonErrors.first?.answer, "on")
    }

    func testDecodeParagraphItems() throws {
        let json = """
        [
          {"word":"serendipity","cefr":"C1","pos":"noun","meaning_vi":"sự tình cờ may mắn","reason_to_learn":"useful, low frequency"},
          {"word":"ubiquitous","cefr":"C1","pos":"adjective","meaning_vi":"có mặt khắp nơi","reason_to_learn":"academic"}
        ]
        """
        let items = try JSONCleaning.decode([ParagraphItem].self, from: json)
        XCTAssertEqual(items.count, 2)
        XCTAssertEqual(items[0].word, "serendipity")
        XCTAssertEqual(items[1].reasonToLearn, "academic")
    }

    func testDecodeProductionFeedback() throws {
        let json = """
        {
          "verdict": "minor_error",
          "corrected_sentence": "I have lived here for five years.",
          "diff": [
            {"type":"keep","text":"I have "},
            {"type":"del","text":"live"},
            {"type":"ins","text":"lived"},
            {"type":"keep","text":" here for five years."}
          ],
          "explanation_vi": "Dùng thì hiện tại hoàn thành.",
          "suggested_rating": "hard"
        }
        """
        let fb = try JSONCleaning.decode(ProductionFeedback.self, from: json)
        XCTAssertEqual(fb.verdict, "minor_error")
        XCTAssertEqual(fb.diff.count, 4)
        XCTAssertEqual(fb.diff[1].type, "del")
        XCTAssertEqual(fb.diff[2].text, "lived")
        XCTAssertEqual(fb.suggestedGrade, .hard)
    }

    func testDecodeFailureThrowsDecodeError() {
        XCTAssertThrowsError(try JSONCleaning.decode(WordCard.self, from: "not json at all")) { error in
            guard case AgyError.decodeFailure = error else {
                return XCTFail("expected decodeFailure, got \(error)")
            }
        }
    }

    func test_entry_analysisState_defaultsReady() {
        let e = Entry(rawText: "x", type: "word", language: "en", capturedAt: Date(), aiResult: "{}")
        XCTAssertEqual(e.analysisState, AnalysisState.ready.rawValue)
    }

    func testWordCardDecodesCategory() throws {
        let json = #"{"meaning_vi":"x","category":"Technology"}"#
        let card = try JSONCleaning.decode(WordCard.self, from: json)
        XCTAssertEqual(card.category, "Technology")
    }

    func testParagraphItemDecodesCategory() throws {
        let json = #"{"word":"router","category":"Technology"}"#
        let item = try JSONCleaning.decode(ParagraphItem.self, from: json)
        XCTAssertEqual(item.category, "Technology")
    }

    func testWordCardDecodesContextOfUseAndGrammarNote() throws {
        let json = #"""
        {
          "meaning_vi": "quyết định",
          "context_of_use": "Dùng trong văn viết trang trọng và các tình huống nghề nghiệp.",
          "grammar_note": "Thường dùng với thì hiện tại đơn và hiện tại hoàn thành."
        }
        """#
        let card = try JSONCleaning.decode(WordCard.self, from: json)
        XCTAssertEqual(card.contextOfUse, "Dùng trong văn viết trang trọng và các tình huống nghề nghiệp.")
        XCTAssertEqual(card.grammarNote, "Thường dùng với thì hiện tại đơn và hiện tại hoàn thành.")
    }

    func testPhraseCardDecodesContextOfUseAndGrammarNote() throws {
        let json = #"""
        {
          "meaning_vi": "từ bỏ",
          "context_of_use": "Dùng trong giao tiếp hàng ngày và văn nói không trang trọng.",
          "grammar_note": "Theo sau bởi danh từ hoặc V-ing; thường dùng với thì quá khứ đơn."
        }
        """#
        let card = try JSONCleaning.decode(PhraseCard.self, from: json)
        XCTAssertEqual(card.contextOfUse, "Dùng trong giao tiếp hàng ngày và văn nói không trang trọng.")
        XCTAssertEqual(card.grammarNote, "Theo sau bởi danh từ hoặc V-ing; thường dùng với thì quá khứ đơn.")
    }

    func testWordCardContextFieldsNilWhenAbsent() throws {
        let json = #"{"meaning_vi":"x"}"#
        let card = try JSONCleaning.decode(WordCard.self, from: json)
        XCTAssertNil(card.contextOfUse)
        XCTAssertNil(card.grammarNote)
    }

    func testPhraseCardContextFieldsNilWhenAbsent() throws {
        let json = #"{"meaning_vi":"y"}"#
        let card = try JSONCleaning.decode(PhraseCard.self, from: json)
        XCTAssertNil(card.contextOfUse)
        XCTAssertNil(card.grammarNote)
    }
}
