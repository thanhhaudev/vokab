import XCTest
@testable import VokabKit

/// Real core + enrich calls against agy. Gated by VOKAB_AGY_INTEGRATION=1.
final class TwoTierTests: XCTestCase {
    func testCoreThenEnrich() async throws {
        try IntegrationGate.skipUnlessEnabled()
        let settings = VokabSettings(timeoutSeconds: 90)
        let agy = AgyService(runner: AgyClient(settings: settings), settings: settings)

        let core = try await agy.defineWordCore("serendipity", language: "en", taxonomy: [])
        XCTAssertTrue((core.meaning?.isEmpty == false) || (core.meaningEn?.isEmpty == false),
                      "core should have a meaning")

        async let extras = agy.enrichWordExtras("serendipity", language: "en")
        async let relations = agy.enrichWordRelations("serendipity", language: "en")
        let merged = core.merging(try await extras).merging(try await relations)
        // Enrichment should add at least one tier-2 field.
        XCTAssertFalse(merged.synonyms.isEmpty && merged.etymology == nil && merged.wordFamily.isEmpty,
                       "enrichment should add synonyms / etymology / word family")
    }
}
