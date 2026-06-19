import XCTest
import GRDB
@testable import VokabKit

final class BatchEnricherTests: XCTestCase {

    /// Content-aware mock: routes by prompt so concurrent extras/relations batch
    /// calls (dispatched via `async let`, nondeterministic order) and the per-item
    /// fallback's single-word calls each get the right canned response regardless
    /// of arrival order. Records every prompt for call-count assertions.
    private final class RoutingRunner: AgyRunner, @unchecked Sendable {
        private let lock = NSLock()
        private(set) var receivedPrompts: [String] = []
        /// Predicate → response. First matching entry wins.
        private let routes: [(@Sendable (String) -> Bool, String)]

        init(routes: [(@Sendable (String) -> Bool, String)]) { self.routes = routes }

        var prompts: [String] { lock.lock(); defer { lock.unlock() }; return receivedPrompts }

        /// Number of batch calls (prompt mentions "For EACH of these words").
        var batchCallCount: Int { prompts.filter { $0.contains("For EACH of these words") }.count }
        /// Number of single-word calls (the per-item fallback path).
        var singleCallCount: Int { prompts.filter { !$0.contains("For EACH of these words") }.count }

        func run(prompt: String, model: String?) async throws -> String {
            lock.lock(); receivedPrompts.append(prompt); lock.unlock()
            for (matches, response) in routes where matches(prompt) {
                return response
            }
            throw AgyError.nonZeroExit(code: 1, stderr: "no route for prompt: \(prompt.prefix(60))")
        }
    }

    /// A typed word whose core fields are present → "batchable" (no core fetch).
    private func insertTypedWord(_ entries: EntryRepository, _ text: String) throws -> Int64 {
        try entries.insertCapture(
            Entry(rawText: text, type: CardType.word.rawValue, language: "en",
                  capturedAt: Date(),
                  aiResult: #"{"pos":"adjective","ipa":"/x/","meaning_en":"brief"}"#),
            dueDate: Date())
    }

    private func makeStack(_ runner: AgyRunner)
        -> (EntryRepository, BatchEnricher) {
        let q = try! VokabDatabase.makeInMemory()
        let entries = EntryRepository(dbQueue: q)
        let agy = AgyService(runner: runner, settings: VokabSettings())
        let fallback = EnrichmentService(agy: agy, entries: entries)
        let batch = BatchEnricher(agy: agy, entries: entries, fallback: fallback)
        return (entries, batch)
    }

    func test_threeIdsCoalesceToOneBatch() async throws {
        let extras = #"[{"word":"alpha","etymology":"a"},{"word":"beta","etymology":"b"},{"word":"gamma","etymology":"g"}]"#
        let relations = #"[{"word":"alpha","synonyms":["a1"]},{"word":"beta","synonyms":["b1"]},{"word":"gamma","synonyms":["g1"]}]"#
        let runner = RoutingRunner(routes: [
            ({ $0.contains("For EACH of these words") && $0.contains("etymology") }, extras),
            ({ $0.contains("For EACH of these words") }, relations),
        ])
        let (entries, batch) = makeStack(runner)
        let ids = try ["alpha", "beta", "gamma"].map { try insertTypedWord(entries, $0) }

        for id in ids { await batch.submit(id: id) }
        await batch.waitQuiescent()

        XCTAssertEqual(runner.batchCallCount, 2, "exactly one extras-batch + one relations-batch (2 total)")
        XCTAssertEqual(runner.singleCallCount, 0, "no per-item fallback when batch covers all")
        for id in ids {
            XCTAssertTrue(try XCTUnwrap(entries.entry(id: id)).enriched, "entry \(id) must be enriched")
        }
    }

    func test_missingWordFallsBackPerItem() async throws {
        // Batch responses OMIT "beta" — its per-item fallback must still enrich it.
        let extras = #"[{"word":"alpha","etymology":"a"},{"word":"gamma","etymology":"g"}]"#
        let relations = #"[{"word":"alpha","synonyms":["a1"]},{"word":"gamma","synonyms":["g1"]}]"#
        let runner = RoutingRunner(routes: [
            ({ $0.contains("For EACH of these words") && $0.contains("etymology") }, extras),
            ({ $0.contains("For EACH of these words") }, relations),
            // Per-item fallback single-word calls for "beta":
            ({ !$0.contains("For EACH of these words") && $0.contains("etymology") }, #"{"etymology":"b"}"#),
            ({ !$0.contains("For EACH of these words") }, #"{"synonyms":["b1"]}"#),
        ])
        let (entries, batch) = makeStack(runner)
        let idA = try insertTypedWord(entries, "alpha")
        let idB = try insertTypedWord(entries, "beta")
        let idG = try insertTypedWord(entries, "gamma")

        for id in [idA, idB, idG] { await batch.submit(id: id) }
        await batch.waitQuiescent()

        XCTAssertTrue(try XCTUnwrap(entries.entry(id: idA)).enriched)
        XCTAssertTrue(try XCTUnwrap(entries.entry(id: idB)).enriched, "omitted word must be enriched via per-item fallback")
        XCTAssertTrue(try XCTUnwrap(entries.entry(id: idG)).enriched)
        XCTAssertGreaterThanOrEqual(runner.singleCallCount, 1, "fallback path must have run for the omitted word")
    }
}
