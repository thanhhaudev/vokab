import XCTest
import GRDB
@testable import VokabKit

/// End-to-end capture against the live agy CLI into an in-memory database.
/// Gated by VOKAB_AGY_INTEGRATION=1.
final class CaptureIntegrationTests: XCTestCase {

    func testRealWordCapturePersistsEntry() async throws {
        try IntegrationGate.skipUnlessEnabled()

        let settings = VokabSettings(timeoutSeconds: 90)
        let queue = try VokabDatabase.makeInMemory()
        let agy = AgyService(runner: AgyClient(settings: settings), settings: settings)
        let entries = EntryRepository(dbQueue: queue)
        let service = CaptureService(
            agy: agy,
            entries: entries,
            cache: CacheRepository(dbQueue: queue),
            quota: QuotaRepository(dbQueue: queue),
            categories: CategoryService(dbQueue: queue),
            settings: settings
        )

        let source = SourceContext(appName: "XCTest", url: nil, capturedAt: Date())
        let result = try await service.capture(text: "serendipity", language: "en", source: source)

        XCTAssertEqual(result.type, .word)
        let id = try XCTUnwrap(result.entryId)
        let entry = try XCTUnwrap(entries.entry(id: id))
        XCTAssertEqual(entry.rawText, "serendipity")

        // The stored ai_result decodes back into a WordCard with a meaning.
        let card = try JSONCleaning.decode(WordCard.self, from: entry.aiResult)
        XCTAssertTrue((card.meaning?.isEmpty == false) || (card.meaningEn?.isEmpty == false))

        // A review_state row was created.
        XCTAssertNotNil(try ReviewRepository(dbQueue: queue).state(entryId: id))
    }
}
