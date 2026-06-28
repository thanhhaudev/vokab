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
        XCTAssertEqual(card.meaning, "ảnh hưởng")   // preserved through the merge
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

final class RelationsBackfillerFormsTests: XCTestCase {
    private func harness(_ json: String) throws -> (RelationsBackfiller, EntryRepository, Int64) {
        let queue = try VokabDatabase.makeInMemory()
        let entries = EntryRepository(dbQueue: queue)
        // A "fully enriched pre-forms" card: has collocations + context + grammar,
        // so the OLD predicate would not backfill — only the new `irregular == nil` does.
        let id = try entries.insertCapture(
            Entry(rawText: "run", type: "word", language: "en", capturedAt: Date(),
                  aiResult: json, enriched: true),
            dueDate: Date())
        let runner = MockAgyRunner([.respond(
            #"{"forms":[{"label":"past","form":"ran"}],"irregular":true,"collocations":["go for a run"],"context_of_use":"x","grammar_note":"y"}"#)])
        let agy = AgyService(runner: runner, settings: VokabSettings())
        return (RelationsBackfiller(agy: agy, entries: entries), entries, id)
    }

    func test_backfillsForms_whenIrregularNil() async throws {
        let (bf, entries, id) = try harness(
            #"{"collocations":["go for a run"],"confusables":[],"context_of_use":"x","grammar_note":"y"}"#)
        _ = try await bf.backfill(entry: try XCTUnwrap(entries.entry(id: id)))
        let card = try JSONCleaning.decode(WordCard.self, from: try XCTUnwrap(entries.entry(id: id)).aiResult)
        XCTAssertEqual(card.forms.first?.form, "ran")
        XCTAssertEqual(card.irregular, true)
    }

    func test_noBackfill_whenIrregularAlreadySet() async throws {
        // irregular already false → forms were fetched (empty is legitimate) → no agy call.
        let (bf, entries, id) = try harness(
            #"{"collocations":["go for a run"],"confusables":[],"forms":[],"irregular":false,"context_of_use":"x","grammar_note":"y"}"#)
        let before = try XCTUnwrap(entries.entry(id: id)).aiResult
        _ = try await bf.backfill(entry: try XCTUnwrap(entries.entry(id: id)))
        XCTAssertEqual(try XCTUnwrap(entries.entry(id: id)).aiResult, before)  // unchanged
    }

    /// A card enriched between the forms feature and the per-form fields: it has
    /// collocations/context/grammar/irregular ALL set but BARE forms (no gloss).
    /// The old predicate wouldn't backfill; the forms-lack-detail clause must, and
    /// merging must upgrade the bare forms to the detailed ones.
    func test_backfillsPerFormDetail_whenFormsAreBare() async throws {
        let queue = try VokabDatabase.makeInMemory()
        let entries = EntryRepository(dbQueue: queue)
        let id = try entries.insertCapture(
            Entry(rawText: "miss", type: "word", language: "en", capturedAt: Date(),
                  aiResult: #"{"collocations":["miss out"],"confusables":[{"word":"mis","note_vi":"x"}],"forms":[{"label":"past","form":"missed"}],"irregular":false,"context_of_use":"x","grammar_note":"y"}"#,
                  enriched: true),
            dueDate: Date())
        let runner = MockAgyRunner([.respond(
            #"{"forms":[{"label":"past","form":"missed","gloss":"đã bỏ lỡ","examples":["I missed it."]}],"irregular":false,"collocations":["miss out"],"context_of_use":"x","grammar_note":"y"}"#)])
        let bf = RelationsBackfiller(agy: AgyService(runner: runner, settings: VokabSettings()), entries: entries)
        _ = try await bf.backfill(entry: try XCTUnwrap(entries.entry(id: id)))
        let card = try JSONCleaning.decode(WordCard.self, from: try XCTUnwrap(entries.entry(id: id)).aiResult)
        XCTAssertEqual(card.forms.first?.gloss, "đã bỏ lỡ")          // detail backfilled + merged
        XCTAssertEqual(card.forms.first?.examples, ["I missed it."])
    }
}
