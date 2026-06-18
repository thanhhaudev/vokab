import XCTest
import GRDB
@testable import VokabKit

final class PhraseErrorBackfillerTests: XCTestCase {
    private let agyJSON = #"{"common_errors":[{"sentence":"Don't give up _____ me.","answer":"on","options":["on","to","at"],"note_vi":"give up + on"}]}"#

    func testBackfillsAndPersistsForEnrichedPhrase() async throws {
        let queue = try VokabDatabase.makeInMemory()
        let entries = EntryRepository(dbQueue: queue)
        let id = try entries.insertCapture(
            Entry(rawText: "give up", type: CardType.phrase.rawValue, language: "en",
                  capturedAt: Date(), aiResult: #"{"meaning_vi":"từ bỏ"}"#), dueDate: Date())
        _ = try entries.markEnriched(id: id, aiResult: #"{"meaning_vi":"từ bỏ"}"#)  // already enriched

        let agy = AgyService(runner: MockAgyRunner(response: agyJSON), settings: VokabSettings())
        let backfiller = PhraseErrorBackfiller(agy: agy, entries: entries)
        _ = try await backfiller.backfill(entry: entries.entry(id: id)!)

        let card = try JSONCleaning.decode(PhraseCard.self, from: entries.entry(id: id)!.aiResult)
        XCTAssertEqual(card.commonErrors.first?.answer, "on")
        XCTAssertEqual(card.meaningVi, "từ bỏ")
    }

    func testSkipsWord() async throws {
        let queue = try VokabDatabase.makeInMemory()
        let entries = EntryRepository(dbQueue: queue)
        let id = try entries.insertCapture(
            Entry(rawText: "router", type: CardType.word.rawValue, language: "en",
                  capturedAt: Date(), aiResult: "{}"), dueDate: Date())
        let backfiller = PhraseErrorBackfiller(
            agy: AgyService(runner: MockAgyRunner(response: agyJSON), settings: VokabSettings()), entries: entries)
        let r = try await backfiller.backfill(entry: entries.entry(id: id)!)
        XCTAssertTrue(try JSONCleaning.decode(PhraseCard.self, from: r!.aiResult).commonErrors.isEmpty)
    }

    func testSkipsAlreadyPopulated() async throws {
        let queue = try VokabDatabase.makeInMemory()
        let entries = EntryRepository(dbQueue: queue)
        let id = try entries.insertCapture(
            Entry(rawText: "give up", type: CardType.phrase.rawValue, language: "en", capturedAt: Date(),
                  aiResult: #"{"common_errors":[{"sentence":"a _____","answer":"x","options":["x"]}]}"#), dueDate: Date())
        let backfiller = PhraseErrorBackfiller(
            agy: AgyService(runner: MockAgyRunner(response: #"{"common_errors":[{"sentence":"b _____","answer":"SHOULD_NOT","options":["SHOULD_NOT"]}]}"#), settings: VokabSettings()), entries: entries)
        let r = try await backfiller.backfill(entry: entries.entry(id: id)!)
        XCTAssertEqual(try JSONCleaning.decode(PhraseCard.self, from: r!.aiResult).commonErrors.first?.answer, "x")
    }
}
