import XCTest
@testable import VokabKit

final class WordFormsTests: XCTestCase {
    func test_decodes_forms_and_irregular() throws {
        let card = try JSONCleaning.decode(WordCard.self, from: #"""
        {"headword":"run","forms":[{"label":"past","form":"ran"},{"label":"-ing","form":"running"}],"irregular":true}
        """#)
        XCTAssertEqual(card.forms.count, 2)
        XCTAssertEqual(card.forms.first?.label, "past")
        XCTAssertEqual(card.forms.first?.form, "ran")
        XCTAssertEqual(card.irregular, true)
    }

    func test_absent_forms_defaultEmpty_irregularNil() throws {
        let card = try JSONCleaning.decode(WordCard.self, from: #"{"pos":"noun"}"#)
        XCTAssertEqual(card.forms, [])
        XCTAssertNil(card.irregular)
    }

    func test_malformed_form_entries_areLenient() throws {
        // A form object missing "form" must not throw the whole decode.
        let card = try JSONCleaning.decode(WordCard.self, from: #"{"forms":[{"label":"past"}]}"#)
        XCTAssertTrue(card.forms.isEmpty)   // empty-form entries are dropped
    }

    func test_merging_fillsFormsWhenEmpty_andIrregularWhenNil() throws {
        let base = try JSONCleaning.decode(WordCard.self, from: #"{"headword":"run"}"#)
        let enrich = try JSONCleaning.decode(WordCard.self,
            from: #"{"forms":[{"label":"plural","form":"runs"}],"irregular":false}"#)
        let merged = base.merging(enrich)
        XCTAssertEqual(merged.forms.first?.form, "runs")
        XCTAssertEqual(merged.irregular, false)
    }

    func test_decodes_perForm_fields() throws {
        let card = try JSONCleaning.decode(WordCard.self, from: #"""
        {"forms":[{"form":"ran","label":"past","gloss":"quá khứ của run","ipa":"/ræn/",
          "usage_note":"kể chuyện quá khứ","common_error":"không phải runned",
          "examples":["He ran home.","They ran fast."]}]}
        """#)
        let f = try XCTUnwrap(card.forms.first)
        XCTAssertEqual(f.gloss, "quá khứ của run")
        XCTAssertEqual(f.ipa, "/ræn/")
        XCTAssertEqual(f.usageNote, "kể chuyện quá khứ")
        XCTAssertEqual(f.commonError, "không phải runned")
        XCTAssertEqual(f.examples, ["He ran home.", "They ran fast."])
    }

    func test_perForm_fields_absent_areNilOrEmpty() throws {
        let card = try JSONCleaning.decode(WordCard.self, from: #"{"forms":[{"form":"runs","label":"3rd-person"}]}"#)
        let f = try XCTUnwrap(card.forms.first)
        XCTAssertNil(f.gloss); XCTAssertNil(f.ipa); XCTAssertNil(f.usageNote); XCTAssertNil(f.commonError)
        XCTAssertEqual(f.examples, [])
    }
}
