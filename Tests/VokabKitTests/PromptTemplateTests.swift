import XCTest
@testable import VokabKit

final class PromptTemplateTests: XCTestCase {
    func testWordCoreOmitsEnrichFields() {
        let p = PromptTemplates.wordCore("x", language: "en", meaningLanguage: "Vietnamese", taxonomy: [])
        XCTAssertTrue(p.contains("meaning_en"))    // meaning fields present
        XCTAssertFalse(p.contains("meaning_vi"))   // generic `meaning`, not hardcoded vi
        XCTAssertFalse(p.contains("etymology"))
        XCTAssertFalse(p.contains("synonyms"))
        XCTAssertFalse(p.contains("word_family"))
    }

    func testWordEnrichSplitFields() {
        let a = PromptTemplates.wordEnrichExtras("x", language: "en")
        XCTAssertTrue(a.contains("etymology"))
        XCTAssertFalse(a.contains("synonyms"))
        let b = PromptTemplates.wordEnrichRelations("x", language: "en")
        XCTAssertTrue(b.contains("word_family"))
        XCTAssertTrue(b.contains("synonyms"))
        XCTAssertFalse(b.contains("etymology"))
    }

    func testPhraseCoreOmitsEnrichFields() {
        let p = PromptTemplates.phraseCore("x", meaningLanguage: "Vietnamese", taxonomy: [])
        XCTAssertFalse(p.contains("variations"))
        XCTAssertFalse(p.contains("common_errors"))
        XCTAssertTrue(p.contains("formula_pattern"))
    }

    func testWordCorePromptIncludesCategoryAndTaxonomy() {
        let p = PromptTemplates.wordCore("router", language: "en", meaningLanguage: "Vietnamese", taxonomy: ["Technology", "Science"])
        XCTAssertTrue(p.contains("category"))
        XCTAssertTrue(p.contains("Technology, Science"))
        XCTAssertTrue(p.contains("only invent a new one"))
    }

    func testClassifyPromptAsksForCategoryJSON() {
        let p = PromptTemplates.classify("router", language: "en", taxonomy: ["Technology"])
        XCTAssertTrue(p.contains("{category}"))
        XCTAssertTrue(p.contains("Technology"))
    }

    func testWordEnrichRelationsIncludesCollocationsAndConfusables() {
        let p = PromptTemplates.wordEnrichRelations("affect", language: "en")
        XCTAssertTrue(p.contains("collocations"))
        XCTAssertTrue(p.contains("confusables"))
        XCTAssertTrue(p.contains("note_vi"))
        XCTAssertTrue(p.contains("synonyms"))   // still returns the original relations
    }

    func testWordRelationsBackfillReturnsOnlyTheNewFields() {
        let p = PromptTemplates.wordRelationsBackfill("affect", language: "en")
        XCTAssertTrue(p.contains("collocations"))
        XCTAssertTrue(p.contains("confusables"))
        XCTAssertFalse(p.contains("synonyms"))     // lightweight: not the full relations
        XCTAssertFalse(p.contains("word_family"))
    }

    func testPhraseEnrichRelationsHasStructuredErrors() {
        let p = PromptTemplates.phraseEnrichRelations("give up")
        XCTAssertTrue(p.contains("common_errors"))
        XCTAssertTrue(p.contains("sentence"))
        XCTAssertTrue(p.contains("note_vi"))
        XCTAssertTrue(p.contains("variations"))
    }

    func testPhraseErrorsBackfillOnlyErrors() {
        let p = PromptTemplates.phraseErrorsBackfill("give up")
        XCTAssertTrue(p.contains("common_errors"))
        XCTAssertFalse(p.contains("variations"))
        XCTAssertFalse(p.contains("related_phrases"))
    }

    func testWordEnrichRelationsIncludesContextOfUseAndGrammarNote() {
        let p = PromptTemplates.wordEnrichRelations("decide", language: "en")
        XCTAssertTrue(p.contains("context_of_use"))
        XCTAssertTrue(p.contains("grammar_note"))
    }

    func testWordRelationsBackfillIncludesContextOfUseAndGrammarNote() {
        let p = PromptTemplates.wordRelationsBackfill("decide", language: "en")
        XCTAssertTrue(p.contains("context_of_use"))
        XCTAssertTrue(p.contains("grammar_note"))
    }

    func testPhraseEnrichRelationsIncludesContextOfUseAndGrammarNote() {
        let p = PromptTemplates.phraseEnrichRelations("give up")
        XCTAssertTrue(p.contains("context_of_use"))
        XCTAssertTrue(p.contains("grammar_note"))
    }

    func testPhraseErrorsBackfillIncludesContextOfUseAndGrammarNote() {
        let p = PromptTemplates.phraseErrorsBackfill("give up")
        XCTAssertTrue(p.contains("context_of_use"))
        XCTAssertTrue(p.contains("grammar_note"))
    }

    func testTranslatePromptShape() {
        let p = PromptTemplates.translate("Hello world.", language: "Vietnamese")
        XCTAssertTrue(p.contains("translation"))
        XCTAssertTrue(p.contains("Vietnamese"))
        XCTAssertTrue(p.contains("Hello world."))
    }

    func test_categoryPrompts_hintHumanReadable() {
        let p = PromptTemplates.wordCore("stubborn", language: "en", meaningLanguage: "Vietnamese", taxonomy: ["Technology"])
        XCTAssertTrue(p.contains("Title Case") || p.lowercased().contains("human-readable"))
        let c = PromptTemplates.classify("stubborn", language: "en", taxonomy: ["Technology"])
        XCTAssertTrue(c.contains("Title Case") || c.lowercased().contains("human-readable"))
    }

    func testParagraphPromptReturnsItemsOnly() {
        let p = PromptTemplates.paragraph("Some text.", minLevel: .b1, meaningLanguage: "Vietnamese", taxonomy: ["Business"])
        XCTAssertFalse(p.contains("translation_vi"))   // translation is fetched separately now
        XCTAssertTrue(p.contains("\"items\""))
        XCTAssertTrue(p.contains("B1"))
        XCTAssertTrue(p.contains("Business"))
    }

    func testParagraphPromptIsExhaustive() {
        let p = PromptTemplates.paragraph("Some text.", minLevel: .a1, meaningLanguage: "Vietnamese", taxonomy: [])
        XCTAssertTrue(p.lowercased().contains("every"))     // list EVERY word
        XCTAssertTrue(p.lowercased().contains("do not"))    // do not cap / omit
    }
}
