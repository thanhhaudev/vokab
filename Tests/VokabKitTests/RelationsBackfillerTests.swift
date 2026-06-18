import XCTest
import GRDB
@testable import VokabKit

final class RelationsBackfillerTests: XCTestCase {
    func testBackfillsMissingRelationsFromAgy() async throws {
        let queue = try VokabDatabase.makeInMemory()
        let entries = EntryRepository(dbQueue: queue)
        let id = try entries.insertCapture(
            Entry(rawText: "affect", type: CardType.word.rawValue, language: "en",
                  capturedAt: Date(), aiResult: #"{"meaning_vi":"ảnh hưởng"}"#), dueDate: Date())

        let runner = MockAgyRunner(response: #"{"collocations":["affect the outcome"],"confusables":[{"word":"effect","note_vi":"danh từ"}]}"#)
        let agy = AgyService(runner: runner, settings: VokabSettings())
        let backfiller = RelationsBackfiller(agy: agy, entries: entries)

        let updated = try await backfiller.backfill(entry: entries.entry(id: id)!)
        let card = try JSONCleaning.decode(WordCard.self, from: updated!.aiResult)
        XCTAssertEqual(card.collocations, ["affect the outcome"])
        XCTAssertEqual(card.confusables.first?.word, "effect")
        XCTAssertEqual(card.meaningVi, "ảnh hưởng")   // preserved through the merge
    }

    func testSkipsWhenAlreadyPopulated() async throws {
        let queue = try VokabDatabase.makeInMemory()
        let entries = EntryRepository(dbQueue: queue)
        let id = try entries.insertCapture(
            Entry(rawText: "affect", type: CardType.word.rawValue, language: "en",
                  capturedAt: Date(), aiResult: #"{"collocations":["already here"]}"#), dueDate: Date())
        let runner = MockAgyRunner(response: #"{"collocations":["SHOULD NOT APPEAR"]}"#)
        let backfiller = RelationsBackfiller(agy: AgyService(runner: runner, settings: VokabSettings()),
                                             entries: entries)
        let result = try await backfiller.backfill(entry: entries.entry(id: id)!)
        let card = try JSONCleaning.decode(WordCard.self, from: result!.aiResult)
        XCTAssertEqual(card.collocations, ["already here"])
    }

    func testPersistsForAlreadyEnrichedEntry() async throws {
        let queue = try VokabDatabase.makeInMemory()
        let entries = EntryRepository(dbQueue: queue)
        let id = try entries.insertCapture(
            Entry(rawText: "affect", type: CardType.word.rawValue, language: "en",
                  capturedAt: Date(), aiResult: #"{"meaning_vi":"ảnh hưởng"}"#), dueDate: Date())
        // Simulate a fully-enriched entry that predates the new fields.
        _ = try entries.markEnriched(id: id, aiResult: #"{"meaning_vi":"ảnh hưởng"}"#)

        let runner = MockAgyRunner(response: #"{"collocations":["affect the outcome"],"confusables":[{"word":"effect","note_vi":"danh từ"}]}"#)
        let backfiller = RelationsBackfiller(agy: AgyService(runner: runner, settings: VokabSettings()),
                                             entries: entries)
        _ = try await backfiller.backfill(entry: entries.entry(id: id)!)

        // Re-read straight from the DB to prove it actually persisted.
        let persisted = try JSONCleaning.decode(WordCard.self, from: entries.entry(id: id)!.aiResult)
        XCTAssertEqual(persisted.collocations, ["affect the outcome"])
        XCTAssertEqual(persisted.confusables.first?.word, "effect")
    }

    func testSkipsNonWordEntries() async throws {
        let queue = try VokabDatabase.makeInMemory()
        let entries = EntryRepository(dbQueue: queue)
        let id = try entries.insertCapture(
            Entry(rawText: "look forward to", type: CardType.phrase.rawValue, language: "en",
                  capturedAt: Date(), aiResult: "{}"), dueDate: Date())
        let runner = MockAgyRunner(response: #"{"collocations":["x"]}"#)
        let backfiller = RelationsBackfiller(agy: AgyService(runner: runner, settings: VokabSettings()),
                                             entries: entries)
        let result = try await backfiller.backfill(entry: entries.entry(id: id)!)
        let card = try JSONCleaning.decode(WordCard.self, from: result!.aiResult)
        XCTAssertTrue(card.collocations.isEmpty)
    }
}
