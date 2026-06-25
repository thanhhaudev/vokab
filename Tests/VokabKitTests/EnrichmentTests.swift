import XCTest
import GRDB
@testable import VokabKit

final class EnrichmentTests: XCTestCase {
    func testEnrichMergesAndMarks() async throws {
        let q = try VokabDatabase.makeInMemory()
        let entries = EntryRepository(dbQueue: q)
        // Typed word: core already present (ipa/meaning_en) → no core fetch, 2 halves.
        let id = try entries.insertCapture(
            Entry(rawText: "ephemeral", type: CardType.word.rawValue, language: "en",
                  capturedAt: Date(), aiResult: #"{"pos":"adjective","meaning_vi":"phù du","ipa":"/x/","meaning_en":"brief"}"#),
            dueDate: Date())
        let runner = MockAgyRunner([
            .respond(#"{"etymology":"Greek ephemeros"}"#),
            .respond(#"{"synonyms":["transient"]}"#)
        ])
        let svc = EnrichmentService(agy: AgyService(runner: runner, settings: VokabSettings()), entries: entries)

        let entry = try XCTUnwrap(entries.entry(id: id))
        let enriched = try await svc.enrich(entry: entry)

        XCTAssertTrue(enriched.enriched)
        let card = try JSONCleaning.decode(WordCard.self, from: enriched.aiResult)
        XCTAssertEqual(card.pos, "adjective")              // core kept
        XCTAssertEqual(card.etymology, "Greek ephemeros")   // enrich added
        XCTAssertEqual(card.synonyms, ["transient"])
    }

    func testEnrichFillsCoreForParagraphWord() async throws {
        let q = try VokabDatabase.makeInMemory()
        let entries = EntryRepository(dbQueue: q)
        // Paragraph-origin word: partial core (no ipa/meaning_en).
        let id = try entries.insertCapture(
            Entry(rawText: "serendipity", type: CardType.word.rawValue, language: "en",
                  capturedAt: Date(), aiResult: #"{"pos":"noun","meaning_vi":"may mắn","cefr_level":"C1"}"#),
            dueDate: Date())
        // core (awaited first) + 2 enrich halves.
        let runner = MockAgyRunner([
            .respond(#"{"ipa":"/ˌsɛrənˈdɪpɪti/","meaning_en":"luck","examples":["e1"]}"#),
            .respond(#"{"etymology":"coined 1754"}"#),
            .respond(#"{"synonyms":["chance"]}"#)
        ])
        let svc = EnrichmentService(agy: AgyService(runner: runner, settings: VokabSettings()), entries: entries)
        let enriched = try await svc.enrich(entry: try XCTUnwrap(entries.entry(id: id)))
        XCTAssertTrue(enriched.enriched)
        let card = try JSONCleaning.decode(WordCard.self, from: enriched.aiResult)
        XCTAssertEqual(card.meaning, "may mắn")    // partial kept
        XCTAssertEqual(card.ipa, "/ˌsɛrənˈdɪpɪti/")   // core filled
        XCTAssertEqual(card.meaningEn, "luck")        // core filled
        XCTAssertEqual(card.etymology, "coined 1754") // enrich filled
        XCTAssertEqual(card.synonyms, ["chance"])     // enrich filled
    }

    func testConcurrentEnrichCoalescesToOneRun() async throws {
        let q = try VokabDatabase.makeInMemory()
        let entries = EntryRepository(dbQueue: q)
        // Typed word (core present) → one enrichment run spends exactly 2 agy calls.
        let id = try entries.insertCapture(
            Entry(rawText: "ephemeral", type: CardType.word.rawValue, language: "en",
                  capturedAt: Date(), aiResult: #"{"pos":"adjective","ipa":"/x/","meaning_en":"brief"}"#),
            dueDate: Date())
        let runner = MockAgyRunner([
            .respond(#"{"etymology":"Greek"}"#),
            .respond(#"{"synonyms":["transient"]}"#)
        ])
        let svc = EnrichmentService(agy: AgyService(runner: runner, settings: VokabSettings()), entries: entries)
        let entry = try XCTUnwrap(entries.entry(id: id))

        // Two concurrent callers for the same id must await the SAME in-flight
        // task — not each spend its own agy calls.
        async let a = svc.enrich(entry: entry)
        async let b = svc.enrich(entry: entry)
        let (ra, rb) = try await (a, b)

        XCTAssertTrue(ra.enriched)
        XCTAssertTrue(rb.enriched)
        XCTAssertEqual(runner.callCount, 2, "duplicate enrich should coalesce, not double the agy calls")
    }

    func testEnrichOnDeletedRowDoesNothing() async throws {
        let q = try VokabDatabase.makeInMemory()
        let entries = EntryRepository(dbQueue: q)
        let id = try entries.insertCapture(
            Entry(rawText: "gone", type: CardType.word.rawValue, language: "en",
                  capturedAt: Date(), aiResult: #"{"pos":"noun","ipa":"/x/","meaning_en":"y"}"#),
            dueDate: Date())
        let entry = try XCTUnwrap(entries.entry(id: id))
        try entries.delete(id: id)   // row vanishes after the caller captured its snapshot

        let runner = MockAgyRunner([])   // throws if called
        let svc = EnrichmentService(agy: AgyService(runner: runner, settings: VokabSettings()), entries: entries)
        // Must not fabricate enrichment from the stale snapshot, and must not spend agy.
        let result = try await svc.enrich(entry: entry)
        XCTAssertFalse(result.enriched)
        XCTAssertEqual(runner.callCount, 0)
    }

    func testEnrichSkipsAlreadyEnriched() async throws {
        let q = try VokabDatabase.makeInMemory()
        let entries = EntryRepository(dbQueue: q)
        let id = try entries.insertCapture(
            Entry(rawText: "x", type: CardType.word.rawValue, language: "en",
                  capturedAt: Date(), aiResult: #"{"pos":"noun"}"#), dueDate: Date())
        try entries.markEnriched(id: id, aiResult: #"{"pos":"noun"}"#)
        let runner = MockAgyRunner([])   // throws if called
        let svc = EnrichmentService(agy: AgyService(runner: runner, settings: VokabSettings()), entries: entries)

        _ = try await svc.enrich(entry: try XCTUnwrap(entries.entry(id: id)))
        XCTAssertEqual(runner.callCount, 0)
    }
}
