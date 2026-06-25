import XCTest
@testable import VokabKit

/// Covers the meaning-language parameterization: Locale-derived language names,
/// the per-card gloss resolution + fallback, legacy `meaning_vi` back-compat, and
/// that capture tags the gloss with its language.
final class MeaningLanguageTests: XCTestCase {

    func testLanguageNameViaLocale() {
        XCTAssertEqual(TranslationService.languageName("vi"), "Vietnamese")
        XCTAssertEqual(TranslationService.languageName("en"), "English")
        XCTAssertEqual(TranslationService.languageName("es"), "Spanish")
        XCTAssertEqual(TranslationService.languageName("ja"), "Japanese")
    }

    func testMeaningResolutionPrefersActiveLanguageThenEnglish() throws {
        // Tagged Spanish gloss + English reference.
        let es = try JSONCleaning.decode(WordCard.self,
            from: #"{"meaning":"casa","meaning_lang":"es","meaning_en":"house"}"#)
        XCTAssertEqual(es.meaning, "casa")
        XCTAssertEqual(es.meaningLang, "es")
        XCTAssertEqual(es.meaning(forLanguage: "es"), "casa")    // active matches tag
        XCTAssertEqual(es.meaning(forLanguage: "fr"), "house")   // mismatch → English ref
        XCTAssertEqual(es.meaning(forLanguage: "en"), "house")   // English mode → English
    }

    func testLegacyMeaningViDecodesAndNeverMislabels() throws {
        // Old stored shape: only meaning_vi (no tag, no English).
        let legacy = try JSONCleaning.decode(WordCard.self, from: #"{"meaning_vi":"nhà"}"#)
        XCTAssertEqual(legacy.meaning, "nhà")
        XCTAssertEqual(legacy.meaningLang, "vi")                  // derived from the legacy key
        XCTAssertEqual(legacy.meaning(forLanguage: "vi"), "nhà")
        XCTAssertNil(legacy.meaning(forLanguage: "es"))          // no English → blank, not Vietnamese
    }

    func testUntaggedMeaningAssumedActiveLanguage() throws {
        let card = try JSONCleaning.decode(WordCard.self, from: #"{"meaning":"gloss"}"#)
        XCTAssertNil(card.meaningLang)
        XCTAssertEqual(card.meaning(forLanguage: "es"), "gloss")  // untagged → assumed active
    }

    func testDefineWordCoreTagsMeaningLanguage() async throws {
        let runner = MockAgyRunner(response: #"{"pos":"noun","meaning":"casa","meaning_en":"house"}"#)
        let agy = AgyService(runner: runner, settings: VokabSettings(meaningLanguage: "es"))
        let card = try await agy.defineWordCore("house", language: "en", taxonomy: [])
        XCTAssertEqual(card.meaning, "casa")
        XCTAssertEqual(card.meaningLang, "es")                    // tagged with the requested language
        XCTAssertTrue(runner.receivedPrompts.first?.contains("Spanish") == true)   // prompt asked in Spanish
    }

    func testPhraseCorePromptNamesMeaningLanguage() {
        let p = PromptTemplates.phraseCore("kick the bucket", meaningLanguage: "Spanish", taxonomy: [])
        XCTAssertTrue(p.contains("Spanish"))
        XCTAssertFalse(p.contains("meaning_vi"))
    }
}
