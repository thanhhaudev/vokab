import XCTest
@testable import VokabKit

/// Contract tests against the live `agy` CLI. Gated by VOKAB_AGY_INTEGRATION=1.
/// Assertions check JSON *structure* (keys/types present and decodable), never
/// exact content, because agy is an LLM and its wording is nondeterministic.
final class AgyContractTests: XCTestCase {

    private func makeService() -> AgyService {
        // Generous timeout for real network round-trips.
        let settings = VokabSettings(timeoutSeconds: 90)
        return AgyService(runner: AgyClient(settings: settings), settings: settings)
    }

    func testWordContract() async throws {
        try IntegrationGate.skipUnlessEnabled()
        let card = try await makeService().defineWord("ephemeral", language: "en")
        // At least one meaning should be present; pos is expected for a word.
        XCTAssertTrue((card.meaning?.isEmpty == false) || (card.meaningEn?.isEmpty == false),
                      "expected a meaning in word card")
        XCTAssertNotNil(card.pos)
    }

    func testPhraseContract() async throws {
        try IntegrationGate.skipUnlessEnabled()
        let card = try await makeService().analyzePhrase("give up on")
        XCTAssertTrue((card.meaning?.isEmpty == false) || (card.meaningEn?.isEmpty == false),
                      "expected a meaning in phrase card")
    }

    func testParagraphContract() async throws {
        try IntegrationGate.skipUnlessEnabled()
        let text = "The ubiquitous nature of smartphones has engendered a profound, " +
                   "perhaps ephemeral, shift in how we cultivate attention."
        let extraction = try await makeService().extractFromParagraph(text, taxonomy: [])
        XCTAssertFalse(extraction.items.isEmpty, "expected at least one extracted item")
        XCTAssertNotNil(extraction.items.first?.word)
    }

    func testProductionContract() async throws {
        try IntegrationGate.skipUnlessEnabled()
        let fb = try await makeService().judgeProduction(word: "ephemeral",
                                                         sentence: "The beauty was ephemeral and gone by dawn.")
        XCTAssertNotNil(fb.verdict)
        // diff must be a structured array of keep/del/ins tokens (SPEC §7d).
        for token in fb.diff {
            XCTAssertTrue(["keep", "del", "ins"].contains(token.type),
                          "unexpected diff token type: \(token.type)")
        }
    }
}
