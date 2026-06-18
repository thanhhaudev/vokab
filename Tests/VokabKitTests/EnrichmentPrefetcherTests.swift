import XCTest
import GRDB
@testable import VokabKit

final class EnrichmentPrefetcherTests: XCTestCase {

    /// Inserts a typed word whose core fields are present, so enrichment spends
    /// exactly 2 agy calls (extras + relations) — no core fetch.
    private func insertTypedWord(_ entries: EntryRepository, _ text: String) throws -> Int64 {
        try entries.insertCapture(
            Entry(rawText: text, type: CardType.word.rawValue, language: "en",
                  capturedAt: Date(),
                  aiResult: #"{"pos":"adjective","ipa":"/x/","meaning_en":"brief"}"#),
            dueDate: Date())
    }

    private func makeService(_ entries: EntryRepository, steps: [MockAgyRunner.Step])
        -> (EnrichmentService, MockAgyRunner) {
        let runner = MockAgyRunner(steps)
        let svc = EnrichmentService(agy: AgyService(runner: runner, settings: VokabSettings()),
                                    entries: entries)
        return (svc, runner)
    }

    func testPrefetchEnrichesEntry() async throws {
        let q = try VokabDatabase.makeInMemory()
        let entries = EntryRepository(dbQueue: q)
        let id = try insertTypedWord(entries, "ephemeral")
        let (svc, _) = makeService(entries, steps: [
            .respond(#"{"etymology":"Greek"}"#),
            .respond(#"{"synonyms":["transient"]}"#)
        ])

        let done = expectation(description: "enriched")
        let prefetcher = EnrichmentPrefetcher(
            enrichment: svc, entries: entries,
            onChange: { done.fulfill() })
        await prefetcher.prefetch(id: id)
        await fulfillment(of: [done], timeout: 5)

        let entry = try XCTUnwrap(entries.entry(id: id))
        XCTAssertTrue(entry.enriched)
    }

    func testPrefetchIdsEnrichesAll() async throws {
        let q = try VokabDatabase.makeInMemory()
        let entries = EntryRepository(dbQueue: q)
        let id1 = try insertTypedWord(entries, "ephemeral")
        let id2 = try insertTypedWord(entries, "serene")
        // 2 calls per word.
        let (svc, _) = makeService(entries, steps: [
            .respond(#"{"etymology":"a"}"#), .respond(#"{"synonyms":["b"]}"#),
            .respond(#"{"etymology":"c"}"#), .respond(#"{"synonyms":["d"]}"#)
        ])

        let done = expectation(description: "both enriched")
        done.expectedFulfillmentCount = 2
        let prefetcher = EnrichmentPrefetcher(
            enrichment: svc, entries: entries,
            onChange: { done.fulfill() })
        await prefetcher.prefetch(ids: [id1, id2])
        await fulfillment(of: [done], timeout: 5)

        XCTAssertTrue(try XCTUnwrap(entries.entry(id: id1)).enriched)
        XCTAssertTrue(try XCTUnwrap(entries.entry(id: id2)).enriched)
    }

    func testPrefetchDeletedIdSpendsNoAgy() async throws {
        let q = try VokabDatabase.makeInMemory()
        let entries = EntryRepository(dbQueue: q)
        let id = try insertTypedWord(entries, "gone")
        try entries.delete(id: id)
        let (svc, runner) = makeService(entries, steps: [])   // throws if called

        // Nothing to enrich → onChange never fires; give the scheduled task a beat.
        let prefetcher = EnrichmentPrefetcher(
            enrichment: svc, entries: entries, onChange: {})
        await prefetcher.prefetch(id: id)
        try await Task.sleep(nanoseconds: 200_000_000)

        XCTAssertEqual(runner.callCount, 0)
    }

    func testPrefetchCoalescesWithConcurrentDetailEnrich() async throws {
        // The whole feature rests on this: a prefetch in flight and the detail
        // view's own enrich() for the same id must collapse to ONE enrichment run
        // (2 agy calls), never two. `EnrichmentService` is an actor that records
        // the in-flight task before suspending, so whichever reaches it first wins
        // and the other coalesces — only 2 responses are queued, so a double run
        // would exhaust the mock and throw.
        let q = try VokabDatabase.makeInMemory()
        let entries = EntryRepository(dbQueue: q)
        let id = try insertTypedWord(entries, "ephemeral")
        let (svc, runner) = makeService(entries, steps: [
            .respond(#"{"etymology":"Greek"}"#),
            .respond(#"{"synonyms":["transient"]}"#)
        ])
        let entry = try XCTUnwrap(entries.entry(id: id))

        let done = expectation(description: "prefetch enriched")
        let prefetcher = EnrichmentPrefetcher(
            enrichment: svc, entries: entries,
            onChange: { done.fulfill() })

        // Fire the background prefetch and the detail-open enrich concurrently.
        await prefetcher.prefetch(id: id)
        let direct = try await svc.enrich(entry: entry)
        await fulfillment(of: [done], timeout: 5)

        XCTAssertTrue(direct.enriched)
        XCTAssertTrue(try XCTUnwrap(entries.entry(id: id)).enriched)
        XCTAssertEqual(runner.callCount, 2, "concurrent prefetch + detail enrich must coalesce, not double agy calls")
    }
}
