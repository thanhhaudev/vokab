import XCTest
@testable import VokabKit

final class WordCardHeadwordTests: XCTestCase {
    func test_decodes_headword() throws {
        let card = try JSONCleaning.decode(WordCard.self,
            from: #"{"headword":"run","senses":[{"pos":"verb","meaning":"chạy"}]}"#)
        XCTAssertEqual(card.headword, "run")
    }

    func test_headword_absent_isNil() throws {
        let card = try JSONCleaning.decode(WordCard.self, from: #"{"pos":"noun"}"#)
        XCTAssertNil(card.headword)
    }

    func test_wordCore_prompt_asksForHeadword() {
        let p = PromptTemplates.wordCore("running", language: "en",
                                         meaningLanguage: "Vietnamese", taxonomy: [])
        XCTAssertTrue(p.lowercased().contains("headword"))
        XCTAssertTrue(p.lowercased().contains("lemma"))
    }
}
