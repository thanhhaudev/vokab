import XCTest
import GRDB
@testable import VokabKit

final class CaptureServiceTests: XCTestCase {

    private struct Harness {
        let service: CaptureService
        let runner: MockAgyRunner
        let entries: EntryRepository
        let cache: CacheRepository
        let quota: QuotaRepository
        let queue: DatabaseQueue
    }

    private func makeHarness(_ steps: [MockAgyRunner.Step],
                             settings: VokabSettings = VokabSettings()) throws -> Harness {
        let queue = try VokabDatabase.makeInMemory()
        let runner = MockAgyRunner(steps)
        let agy = AgyService(runner: runner, settings: settings)
        let entries = EntryRepository(dbQueue: queue)
        let cache = CacheRepository(dbQueue: queue)
        let quota = QuotaRepository(dbQueue: queue)
        let categories = CategoryService(dbQueue: queue)
        let service = CaptureService(agy: agy, entries: entries, cache: cache, quota: quota,
                                     categories: categories, settings: settings)
        return Harness(service: service, runner: runner, entries: entries,
                       cache: cache, quota: quota, queue: queue)
    }

    private func source(_ now: Date) -> SourceContext {
        SourceContext(appName: "Safari", url: "https://example.com", capturedAt: now)
    }

    func testSuccessfulWordCapturePersistsEverything() async throws {
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let h = try makeHarness([.respond(#"{"pos":"adjective","meaning_vi":"phù du","cefr_level":"C1","frequency":"low"}"#)])

        let result = try await h.service.capture(text: "ephemeral", language: "en", source: source(now))

        XCTAssertEqual(result.type, .word)
        XCTAssertFalse(result.wasDuplicate)
        let id = try XCTUnwrap(result.entryId)

        let entry = try XCTUnwrap(h.entries.entry(id: id))
        XCTAssertEqual(entry.cefr, "c1")               // denormalized + lowercased
        XCTAssertEqual(entry.language, "en")
        XCTAssertEqual(entry.sourceApp, "Safari")
        XCTAssertNotNil(try ReviewRepository(dbQueue: h.queue).state(entryId: id))
        XCTAssertEqual(try h.quota.count(on: now), 1)  // quota charged
        XCTAssertNotNil(try h.cache.lookup(text: "ephemeral", language: "en")) // cached
    }

    func testWordCaptureCanonicalizesAndStoresCategory() async throws {
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        // agy proposes "technology" (lowercase) → must canonicalize to seed "Technology".
        let h = try makeHarness([.respond(#"{"meaning_vi":"bộ định tuyến","cefr_level":"B2","category":"technology"}"#)])
        let result = try await h.service.capture(text: "router", language: "en", source: source(now))
        let entry = try XCTUnwrap(h.entries.entry(id: try XCTUnwrap(result.entryId)))
        XCTAssertEqual(entry.category, "Technology")
    }

    func testStoredJSONRoundTripsBackToCard() async throws {
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let h = try makeHarness([.respond(#"{"pos":"noun","meaning_vi":"nghĩa","synonyms":["a","b"]}"#)])
        let result = try await h.service.capture(text: "thing", language: "en", source: source(now))
        let entry = try XCTUnwrap(h.entries.entry(id: try XCTUnwrap(result.entryId)))
        let card = try JSONCleaning.decode(WordCard.self, from: entry.aiResult)
        XCTAssertEqual(card.pos, "noun")
        XCTAssertEqual(card.synonyms, ["a", "b"])
    }

    func testDuplicateSkipsAgy() async throws {
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let h = try makeHarness([.respond(#"{"pos":"noun"}"#)])
        let original = try await h.service.capture(text: "word", language: "en", source: source(now))
        let before = h.runner.callCount

        let dup = try await h.service.capture(text: "WORD", language: "en", source: source(now))
        XCTAssertTrue(dup.wasDuplicate)
        XCTAssertEqual(h.runner.callCount, before)     // no extra agy call
        // A duplicate returns the EXISTING entry's id and inserts no new row.
        // (This is why an "Undo = delete by id" on a duplicate would destroy the
        // user's original — the UI must not offer Undo for duplicates.)
        XCTAssertEqual(dup.entryId, original.entryId)
        XCTAssertEqual(try h.entries.all().count, 1)
    }

    func testCacheHitSkipsAgy() async throws {
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let h = try makeHarness([])                    // runner would throw if called
        try h.cache.upsert(text: "cached", language: "en",
                           aiResult: #"{"pos":"verb","cefr_level":"B2"}"#, now: now)

        let result = try await h.service.capture(text: "cached", language: "en", source: source(now))
        XCTAssertTrue(result.fromCache)
        XCTAssertEqual(h.runner.callCount, 0)
        let entry = try XCTUnwrap(h.entries.entry(id: try XCTUnwrap(result.entryId)))
        XCTAssertEqual(entry.cefr, "b2")
    }

    func testQuotaExceededThrowsAndDoesNotCallAgy() async throws {
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let settings = VokabSettings(dailyLimit: 1, hardBlockOnLimit: true, quotaHitBehavior: .skip)
        let h = try makeHarness([.respond(#"{"pos":"noun"}"#)], settings: settings)
        try h.quota.increment(on: now)                 // already at limit

        do {
            _ = try await h.service.capture(text: "blocked", language: "en", source: source(now))
            XCTFail("expected quotaExceeded")
        } catch CaptureError.quotaExceeded(let behavior) {
            XCTAssertEqual(behavior, .skip)
            XCTAssertEqual(h.runner.callCount, 0)
        }
    }

    func testTimeoutWritesNothingAndChargesNoQuota() async throws {
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let h = try makeHarness([.fail(.timeout)])
        do {
            _ = try await h.service.capture(text: "slow", language: "en", source: source(now))
            XCTFail("expected timeout")
        } catch AgyError.timeout {
            XCTAssertEqual(try h.entries.all().count, 0) // no entry
            XCTAssertEqual(try h.quota.count(on: now), 0) // no quota charge
        }
    }

    func testParagraphReturnsItemsAndChargesQuota() async throws {
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let h = try makeHarness([.respond(#"{"translation_vi":"Bản dịch.","items":[{"word":"ubiquitous","cefr":"C1"},{"word":"engender","cefr":"C2"}]}"#)])
        let text = "The ubiquitous nature of things engenders change. It is everywhere now."

        let result = try await h.service.capture(text: text, language: "en", source: source(now))
        XCTAssertEqual(result.type, .paragraphItem)
        XCTAssertEqual(result.paragraphItems.count, 2)
        XCTAssertNil(result.entryId)                    // not auto-persisted
        XCTAssertEqual(try h.quota.count(on: now), 1)
        XCTAssertEqual(result.translationVi, "Bản dịch.")
        XCTAssertEqual(result.failedChunks, 0)

        // Persisting a chosen item creates a first-class WORD entry (so it gets
        // full detail + enrichment, like a typed word) seeded with the item's fields.
        let id = try h.service.persistParagraphItem(result.paragraphItems[0], language: "en", source: source(now))
        let saved = try XCTUnwrap(h.entries.entry(id: id))
        XCTAssertEqual(saved.cardType, .word)
        XCTAssertFalse(saved.enriched)              // background prep will fill it
        XCTAssertEqual(try JSONCleaning.decode(WordCard.self, from: saved.aiResult).cefrLevel, "C1")
    }

    func testReextractCachesPerMinLevel() async throws {
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let h = try makeHarness([
            .respond(#"{"translation_vi":"t1","items":[{"word":"alpha","cefr":"B2"}]}"#),
            .respond(#"{"translation_vi":"t2","items":[{"word":"beta","cefr":"C1"}]}"#),
        ])
        let text = "some paragraph text worth analyzing here"

        let b2 = try await h.service.reextractParagraph(text: text, language: "en", minLevel: .b2, now: now)
        XCTAssertEqual(b2.items.first?.word, "alpha")
        XCTAssertEqual(h.runner.callCount, 1)

        // Same level → cache hit, no extra agy call.
        let b2again = try await h.service.reextractParagraph(text: text, language: "en", minLevel: .b2, now: now)
        XCTAssertEqual(b2again.items.first?.word, "alpha")
        XCTAssertEqual(h.runner.callCount, 1)

        // Different level → cache miss, new agy call.
        let c1 = try await h.service.reextractParagraph(text: text, language: "en", minLevel: .c1, now: now)
        XCTAssertEqual(c1.items.first?.word, "beta")
        XCTAssertEqual(h.runner.callCount, 2)
        XCTAssertEqual(try h.quota.count(on: now), 2)        // two real calls charged
    }

    func testReextractCacheHitChargesNoQuota() async throws {
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let h = try makeHarness([])                          // runner throws if called
        try h.cache.upsert(text: "p", language: "en", minLevel: .b1,
                           aiResult: #"{"translation_vi":"t","items":[{"word":"x"}]}"#, now: now)
        let fetch = try await h.service.reextractParagraph(text: "p", language: "en", minLevel: .b1, now: now)
        XCTAssertEqual(fetch.items.first?.word, "x")
        XCTAssertEqual(h.runner.callCount, 0)
        XCTAssertEqual(try h.quota.count(on: now), 0)
    }

    func testReextractQuotaExceededThrows() async throws {
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let settings = VokabSettings(dailyLimit: 1, hardBlockOnLimit: true, quotaHitBehavior: .skip)
        let h = try makeHarness([.respond("[]")], settings: settings)
        try h.quota.increment(on: now)                       // already at limit
        do {
            _ = try await h.service.reextractParagraph(text: "p", language: "en", minLevel: .b2, now: now)
            XCTFail("expected quotaExceeded")
        } catch CaptureError.quotaExceeded {
            XCTAssertEqual(h.runner.callCount, 0)
        }
    }

    func testForcedWordCapturesMultiWordAsSingleEntry() async throws {
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let h = try makeHarness([.respond(#"{"meaning_vi":"mong chờ","cefr_level":"B1"}"#)])
        let result = try await h.service.capture(text: "look forward to", language: "en",
                                                 source: source(now), forcedType: .word)
        XCTAssertEqual(result.type, .word)
        let entry = try XCTUnwrap(h.entries.entry(id: try XCTUnwrap(result.entryId)))
        XCTAssertEqual(entry.cardType, .word)
        XCTAssertEqual(entry.rawText, "look forward to")
    }

    func testForcedPhraseOnSingleToken() async throws {
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let h = try makeHarness([.respond(#"{"type":"idiom","meaning_vi":"x"}"#)])
        let result = try await h.service.capture(text: "ephemeral", language: "en",
                                                 source: source(now), forcedType: .phrase)
        XCTAssertEqual(result.type, .phrase)
    }

    func testForcedParagraphHonorsMinLevelOverride() async throws {
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let h = try makeHarness([.respond(#"{"items":[{"word":"alpha","cefr":"C1"}]}"#)])
        let result = try await h.service.capture(text: "two words here", language: "en",
                                                 source: source(now),
                                                 forcedType: .paragraphItem, minLevelOverride: .c1)
        XCTAssertEqual(result.type, .paragraphItem)
        XCTAssertEqual(result.paragraphItems.first?.word, "alpha")
        XCTAssertNotNil(try h.cache.lookup(text: "two words here", language: "en", minLevel: .c1))
        XCTAssertEqual(try h.quota.count(on: now), 1)
    }

    func testPersistParagraphItemStoresExtractedSentence() async throws {
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let h = try makeHarness([.respond(#"{"items":[{"word":"ubiquitous","cefr":"C1"}]}"#)])
        let text = "The ubiquitous nature of things engenders change. It is everywhere now."
        let result = try await h.service.capture(text: text, language: "en", source: source(now))

        let id = try h.service.persistParagraphItem(result.paragraphItems[0], language: "en",
                                                    source: source(now), sourceText: text)
        let saved = try XCTUnwrap(h.entries.entry(id: id))
        XCTAssertEqual(saved.captureSentence, "The ubiquitous nature of things engenders change.")
    }

    func testPersistParagraphItemWithoutSourceTextStoresNil() async throws {
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let h = try makeHarness([.respond(#"{"items":[{"word":"ubiquitous","cefr":"C1"}]}"#)])
        let text = "The ubiquitous nature of things engenders change."
        let result = try await h.service.capture(text: text, language: "en", source: source(now))

        let id = try h.service.persistParagraphItem(result.paragraphItems[0], language: "en", source: source(now))
        XCTAssertNil(try XCTUnwrap(h.entries.entry(id: id)).captureSentence)
    }

    // MARK: - QuotaStatus (warn-only vs hard-block)

    private func makeCaptureAndQuota(settings: VokabSettings) throws -> (CaptureService, QuotaRepository) {
        let h = try makeHarness([], settings: settings)
        return (h.service, h.quota)
    }

    func test_overWarnThreshold_doesNotBlock_byDefault() throws {
        var settings = VokabSettings(); settings.dailyLimit = 1; settings.hardBlockOnLimit = false
        let (capture, quota) = try makeCaptureAndQuota(settings: settings)
        try quota.increment(on: Date())
        let status = capture.quotaStatus(on: Date())
        XCTAssertTrue(status.overWarn)
        XCTAssertFalse(status.shouldBlock)
    }

    func test_overThreshold_blocks_whenHardBlockOn() throws {
        var settings = VokabSettings(); settings.dailyLimit = 1; settings.hardBlockOnLimit = true
        let (capture, quota) = try makeCaptureAndQuota(settings: settings)
        try quota.increment(on: Date())
        let status = capture.quotaStatus(on: Date())
        XCTAssertTrue(status.shouldBlock)
    }

    // MARK: - Async-first capture (beginCapture + runAnalysis)

    private struct AsyncHarness {
        let capture: CaptureService
        let entries: EntryRepository
        let quota: QuotaRepository
    }

    private func makeHarnessForAsync(wordJSON: String = "{}", failWith: AgyError? = nil,
                                     settings: VokabSettings = VokabSettings()) throws -> AsyncHarness {
        let queue = try VokabDatabase.makeInMemory()
        let steps: [MockAgyRunner.Step] = failWith.map { [.fail($0)] } ?? [.respond(wordJSON)]
        let runner = MockAgyRunner(steps)
        let agy = AgyService(runner: runner, settings: settings)
        let entries = EntryRepository(dbQueue: queue)
        let cache = CacheRepository(dbQueue: queue)
        let quota = QuotaRepository(dbQueue: queue)
        let categories = CategoryService(dbQueue: queue)
        let capture = CaptureService(agy: agy, entries: entries, cache: cache, quota: quota,
                                     categories: categories, settings: settings)
        return AsyncHarness(capture: capture, entries: entries, quota: quota)
    }

    func test_beginCapture_wordMiss_insertsPendingAndNeedsAnalysis() throws {
        // MockAgyRunner not even called by beginCapture.
        let h = try makeHarnessForAsync(wordJSON: #"{"pos":"adjective","cefr_level":"B2"}"#)
        let src = SourceContext(appName: "t", url: nil, capturedAt: Date())
        let began = try h.capture.beginCapture(text: "stubborn", language: "en", source: src)
        guard case let .pending(entryId, type) = began else { return XCTFail("expected pending, got \(began)") }
        XCTAssertEqual(type, .word)
        XCTAssertEqual(try h.entries.entry(id: entryId)?.analysisState, AnalysisState.analyzing.rawValue)
    }

    func test_runAnalysis_fillsResult_andChargesQuotaAfter() async throws {
        let h = try makeHarnessForAsync(wordJSON: #"{"pos":"adjective","cefr_level":"B2","category":"daily_life"}"#)
        let src = SourceContext(appName: "t", url: nil, capturedAt: Date())
        guard case let .pending(id, _) = try h.capture.beginCapture(text: "stubborn", language: "en", source: src)
        else { return XCTFail() }
        XCTAssertEqual(try h.quota.count(on: Date()), 0)
        _ = await h.capture.runAnalysis(entryId: id)
        XCTAssertEqual(try h.entries.entry(id: id)?.analysisState, AnalysisState.ready.rawValue)
        XCTAssertEqual(try h.entries.entry(id: id)?.cefr, "b2")
        XCTAssertEqual(try h.quota.count(on: Date()), 1)
    }

    func test_runAnalysis_agyFailure_marksFailed_noQuota() async throws {
        let h = try makeHarnessForAsync(failWith: AgyError.timeout)
        let src = SourceContext(appName: "t", url: nil, capturedAt: Date())
        guard case let .pending(id, _) = try h.capture.beginCapture(text: "stubborn", language: "en", source: src)
        else { return XCTFail() }
        _ = await h.capture.runAnalysis(entryId: id)
        XCTAssertEqual(try h.entries.entry(id: id)?.analysisState, AnalysisState.failed.rawValue)
        XCTAssertEqual(try h.quota.count(on: Date()), 0)
    }

    func test_beginCapture_duplicate_returnsDuplicate() throws {
        let h = try makeHarnessForAsync(wordJSON: "{}")
        let src = SourceContext(appName: "t", url: nil, capturedAt: Date())
        _ = try h.entries.insertCapture(Entry(rawText: "stubborn", type: "word", language: "en",
            capturedAt: Date(), aiResult: "{}"), dueDate: Date())
        if case .duplicate = try h.capture.beginCapture(text: "stubborn", language: "en", source: src) {} else { XCTFail() }
    }

    // MARK: - Chunked paragraph extraction (Task 7)

    /// 130 words across 13 sentences → 2 chunks at the 120-word threshold.
    private func longText() -> String {
        (1...13).map { i in "word\(i)a word\(i)b word\(i)c word\(i)d word\(i)e word\(i)f word\(i)g word\(i)h word\(i)i sentence\(i)." }
            .joined(separator: " ")
    }

    func testLongParagraphChunksAndMergesAndChargesPerChunk() async throws {
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let h = try makeHarness([
            .respond(#"{"translation_vi":"Phần một. ","items":[{"word":"alpha","cefr":"B2"}]}"#),
            .respond(#"{"translation_vi":"Phần hai.","items":[{"word":"beta","cefr":"C1"},{"word":"alpha","cefr":"B2"}]}"#),
        ])
        let result = try await h.service.capture(text: longText(), language: "en", source: source(now))
        XCTAssertEqual(h.runner.callCount, 2)                       // chunked into 2 calls
        XCTAssertEqual(result.paragraphItems.map { $0.word }, ["alpha", "beta"]) // merged, deduped
        XCTAssertEqual(result.translationVi, "Phần một. Phần hai.")  // concatenated in order
        XCTAssertEqual(try h.quota.count(on: now), 2)              // one per successful chunk
        XCTAssertEqual(result.failedChunks, 0)
    }

    func testPartialChunkFailureKeepsSuccessesAndCountsFailure() async throws {
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        // 1st chunk OK; 2nd chunk fails (timeout) — transport errors are NOT retried.
        let h = try makeHarness([
            .respond(#"{"translation_vi":"OK.","items":[{"word":"alpha","cefr":"B2"}]}"#),
            .fail(.timeout),
        ])
        let result = try await h.service.capture(text: longText(), language: "en", source: source(now))
        XCTAssertEqual(result.paragraphItems.map { $0.word }, ["alpha"]) // success kept
        XCTAssertEqual(result.failedChunks, 1)
        XCTAssertEqual(try h.quota.count(on: now), 1)              // failed chunk not charged
    }

    // MARK: - Task 9: Dedupe guard in persistParagraphItem

    func testPersistParagraphItemSkipsDuplicateAndBackfills() async throws {
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let h = try makeHarness([.respond(#"{"meaning_vi":"nắm bắt","cefr_level":"B2"}"#)])
        // First, capture "grasp" as a word with NO capture sentence.
        _ = try await h.service.capture(text: "grasp", language: "en", source: source(now))
        let before = try h.entries.all()
        XCTAssertEqual(before.count, 1)
        XCTAssertNil(before[0].captureSentence)

        // Now persist a paragraph item for the same word, with source text → backfills sentence.
        let item = try JSONCleaning.decode(ParagraphItem.self, from: #"{"word":"grasp","cefr":"B2"}"#)
        let id = try h.service.persistParagraphItem(item, language: "en", source: source(now),
                                                    sourceText: "I finally grasp the concept.")
        XCTAssertEqual(id, before[0].id)                    // returns existing id
        XCTAssertEqual(try h.entries.all().count, 1)        // no duplicate row
        XCTAssertEqual(try h.entries.entry(id: id)?.captureSentence, "I finally grasp the concept.")
    }

    func testPersistParagraphItemInsertsWhenNew() throws {
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let h = try makeHarness([])
        let item = try JSONCleaning.decode(ParagraphItem.self, from: #"{"word":"novel","cefr":"B2"}"#)
        let id = try h.service.persistParagraphItem(item, language: "en", source: source(now))
        XCTAssertEqual(try h.entries.entry(id: id)?.rawText, "novel")
    }
}
