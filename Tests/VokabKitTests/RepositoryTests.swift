import XCTest
import GRDB
@testable import VokabKit

final class RepositoryTests: XCTestCase {

    private func makeEntry(_ text: String, language: String = "en") -> Entry {
        Entry(rawText: text, type: CardType.word.rawValue, language: language,
              capturedAt: Date(timeIntervalSince1970: 1_700_000_000),
              aiResult: #"{"pos":"noun"}"#, cefr: "b2")
    }

    func testInsertCaptureCreatesEntryAndReviewState() throws {
        let q = try VokabDatabase.makeInMemory()
        let entries = EntryRepository(dbQueue: q)
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let id = try entries.insertCapture(makeEntry("ephemeral"), dueDate: now)

        XCTAssertNotNil(try entries.entry(id: id))
        let review = ReviewRepository(dbQueue: q)
        XCTAssertNotNil(try review.state(entryId: id))
        XCTAssertEqual(try review.state(entryId: id)?.mode, .recognition)
    }

    func testDueCardsRespectsDueDate() throws {
        let q = try VokabDatabase.makeInMemory()
        let entries = EntryRepository(dbQueue: q)
        let base = Date(timeIntervalSince1970: 1_700_000_000)
        _ = try entries.insertCapture(makeEntry("due-now"), dueDate: base.addingTimeInterval(-100))
        _ = try entries.insertCapture(makeEntry("due-future"), dueDate: base.addingTimeInterval(86_400))

        let review = ReviewRepository(dbQueue: q)
        let due = try review.dueCards(on: base)
        XCTAssertEqual(due.count, 1)
        XCTAssertEqual(due.first?.entry.rawText, "due-now")
        XCTAssertEqual(try review.dueCount(on: base), 1)
    }

    func testFindDedupIsCaseInsensitive() throws {
        let q = try VokabDatabase.makeInMemory()
        let entries = EntryRepository(dbQueue: q)
        _ = try entries.insertCapture(makeEntry("Ephemeral"), dueDate: Date())
        XCTAssertNotNil(try entries.find(rawText: "  ephemeral ", language: "en"))
        XCTAssertNil(try entries.find(rawText: "ephemeral", language: "fr"))
    }

    func testCacheUpsertAndLookup() throws {
        let q = try VokabDatabase.makeInMemory()
        let cache = CacheRepository(dbQueue: q)
        let now = Date()
        XCTAssertNil(try cache.lookup(text: "word", language: "en"))
        try cache.upsert(text: "Word", language: "EN", aiResult: #"{"x":1}"#, now: now)
        XCTAssertEqual(try cache.lookup(text: "word", language: "en")?.aiResult, #"{"x":1}"#)
        try cache.clear()
        XCTAssertNil(try cache.lookup(text: "word", language: "en"))
    }

    func testQuotaIncrementAndCount() throws {
        let q = try VokabDatabase.makeInMemory()
        let quota = QuotaRepository(dbQueue: q)
        let day = Date(timeIntervalSince1970: 1_700_000_000)
        XCTAssertEqual(try quota.count(on: day), 0)
        try quota.increment(on: day)
        try quota.increment(on: day, tokens: 50)
        XCTAssertEqual(try quota.count(on: day), 2)
        // A different day is a separate bucket.
        XCTAssertEqual(try quota.count(on: day.addingTimeInterval(86_400 * 2)), 0)
    }

    func testStreakCountsConsecutiveDays() throws {
        let q = try VokabDatabase.makeInMemory()
        let log = ReviewLogRepository(dbQueue: q)
        let cal = Calendar(identifier: .gregorian)
        let today = Date(timeIntervalSince1970: 1_700_000_000)
        // Reviews today, yesterday, two days ago → streak 3.
        try log.record(on: today)
        try log.record(on: cal.date(byAdding: .day, value: -1, to: today)!)
        try log.record(on: cal.date(byAdding: .day, value: -2, to: today)!)
        // A gap at day -4 should not extend the streak.
        try log.record(on: cal.date(byAdding: .day, value: -4, to: today)!)
        XCTAssertEqual(try log.streak(asOf: today, calendar: cal), 3)
    }

    func testStreakAnchorsYesterdayIfNothingToday() throws {
        let q = try VokabDatabase.makeInMemory()
        let log = ReviewLogRepository(dbQueue: q)
        let cal = Calendar(identifier: .gregorian)
        let today = Date(timeIntervalSince1970: 1_700_000_000)
        try log.record(on: cal.date(byAdding: .day, value: -1, to: today)!)
        try log.record(on: cal.date(byAdding: .day, value: -2, to: today)!)
        XCTAssertEqual(try log.streak(asOf: today, calendar: cal), 2)   // not broken yet
    }

    func testStreakZeroWhenStale() throws {
        let q = try VokabDatabase.makeInMemory()
        let log = ReviewLogRepository(dbQueue: q)
        let cal = Calendar(identifier: .gregorian)
        let today = Date(timeIntervalSince1970: 1_700_000_000)
        try log.record(on: cal.date(byAdding: .day, value: -5, to: today)!)
        XCTAssertEqual(try log.streak(asOf: today, calendar: cal), 0)
    }

    func testAllStatesReturnsEveryReviewStateInOneRead() throws {
        let q = try VokabDatabase.makeInMemory()
        let entries = EntryRepository(dbQueue: q)
        let id1 = try entries.insertCapture(makeEntry("a"), dueDate: Date())
        let id2 = try entries.insertCapture(makeEntry("b"), dueDate: Date())
        let states = try ReviewRepository(dbQueue: q).allStates()
        XCTAssertEqual(states.count, 2)
        XCTAssertNotNil(states[id1])
        XCTAssertNotNil(states[id2])
    }

    func testMarkEnrichedIsCompareAndSwap() throws {
        let q = try VokabDatabase.makeInMemory()
        let entries = EntryRepository(dbQueue: q)
        let id = try entries.insertCapture(makeEntry("w"), dueDate: Date())
        XCTAssertTrue(try entries.markEnriched(id: id, aiResult: #"{"etymology":"first"}"#))
        // A second enrichment must NOT clobber the already-enriched row.
        XCTAssertFalse(try entries.markEnriched(id: id, aiResult: #"{"etymology":"second"}"#))
        let e = try entries.entry(id: id)
        XCTAssertEqual(e?.enriched, true)
        XCTAssertTrue(e?.aiResult.contains("first") == true)
        XCTAssertFalse(e?.aiResult.contains("second") == true)
    }

    func testSetCategoryAndCounts() throws {
        let q = try VokabDatabase.makeInMemory()
        let repo = EntryRepository(dbQueue: q)
        let id = try repo.insertCapture(makeEntry("router"), dueDate: Date())
        XCTAssertEqual(try repo.uncategorizedCount(), 1)

        try repo.setCategory(id: id, category: "Technology")
        XCTAssertEqual(try repo.uncategorizedCount(), 0)
        XCTAssertEqual(try repo.categoryCounts(), ["Technology": 1])
    }

    func testDeleteCascadesReviewState() throws {
        let q = try VokabDatabase.makeInMemory()
        let entries = EntryRepository(dbQueue: q)
        let id = try entries.insertCapture(makeEntry("temp"), dueDate: Date())
        try entries.delete(id: id)
        XCTAssertNil(try entries.entry(id: id))
        XCTAssertNil(try ReviewRepository(dbQueue: q).state(entryId: id))
    }

    func test_markAnalyzed_setsFieldsAndState_onlyFromAnalyzing() throws {
        let queue = try VokabDatabase.makeInMemory()
        let repo = EntryRepository(dbQueue: queue)
        let id = try repo.insertCapture(
            Entry(rawText: "stubborn", type: "word", language: "en", capturedAt: Date(),
                  aiResult: "{}", analysisState: AnalysisState.analyzing.rawValue),
            dueDate: Date())
        let did = try repo.markAnalyzed(id: id, aiResult: #"{"pos":"adjective"}"#,
                                        cefr: "B2", frequency: "mid", category: "Daily life")
        XCTAssertTrue(did)
        let e = try repo.entry(id: id)
        XCTAssertEqual(e?.analysisState, AnalysisState.ready.rawValue)
        XCTAssertEqual(e?.cefr, "b2")
        XCTAssertEqual(e?.category, "Daily life")
        XCTAssertFalse(try repo.markAnalyzed(id: id, aiResult: "{}", cefr: nil, frequency: nil, category: nil))
    }

    func test_markAnalysisFailed_andPendingIds() throws {
        let queue = try VokabDatabase.makeInMemory()
        let repo = EntryRepository(dbQueue: queue)
        let id = try repo.insertCapture(
            Entry(rawText: "x", type: "word", language: "en", capturedAt: Date(),
                  aiResult: "{}", analysisState: AnalysisState.analyzing.rawValue), dueDate: Date())
        XCTAssertEqual(try repo.pendingEntryIds(), [id])
        try repo.markAnalysisFailed(id: id)
        XCTAssertEqual(try repo.entry(id: id)?.analysisState, AnalysisState.failed.rawValue)
        XCTAssertEqual(try repo.pendingEntryIds(), [])
    }

    func test_markAnalyzingAgain_requeuesFailedEntry() throws {
        let queue = try VokabDatabase.makeInMemory()
        let repo = EntryRepository(dbQueue: queue)
        let id = try repo.insertCapture(Entry(rawText: "x", type: "word", language: "en",
            capturedAt: Date(), aiResult: "{}", analysisState: AnalysisState.analyzing.rawValue), dueDate: Date())
        try repo.markAnalysisFailed(id: id)
        try repo.markAnalyzingAgain(id: id)
        XCTAssertEqual(try repo.entry(id: id)?.analysisState, AnalysisState.analyzing.rawValue)
        XCTAssertEqual(try repo.pendingEntryIds(), [id])
    }

    func test_allCards_excludesNonReadyEntries() throws {
        let queue = try VokabDatabase.makeInMemory()
        let repo = EntryRepository(dbQueue: queue)
        let now = Date(timeIntervalSince1970: 1_700_000_000)

        // Insert one 'ready' entry (default analysisState = .ready)
        _ = try repo.insertCapture(
            Entry(rawText: "ready-word", type: "word", language: "en", capturedAt: now,
                  aiResult: "{}", analysisState: AnalysisState.ready.rawValue),
            dueDate: now.addingTimeInterval(-1))

        // Insert one 'analyzing' entry — should NOT appear in allCards()
        _ = try repo.insertCapture(
            Entry(rawText: "analyzing-word", type: "word", language: "en", capturedAt: now,
                  aiResult: "{}", analysisState: AnalysisState.analyzing.rawValue),
            dueDate: now.addingTimeInterval(-1))

        let review = ReviewRepository(dbQueue: queue)
        let all = try review.allCards()

        XCTAssertEqual(all.count, 1, "allCards() should exclude non-ready entries")
        XCTAssertEqual(all.first?.entry.rawText, "ready-word")
    }

    func test_review_excludesNonReadyEntries() throws {
        let queue = try VokabDatabase.makeInMemory()
        let repo = EntryRepository(dbQueue: queue)
        let now = Date(timeIntervalSince1970: 1_700_000_000)

        // Insert one 'ready' entry due now (default analysisState = .ready)
        _ = try repo.insertCapture(
            Entry(rawText: "ephemeral", type: "word", language: "en", capturedAt: now,
                  aiResult: "{}", analysisState: AnalysisState.ready.rawValue),
            dueDate: now.addingTimeInterval(-1))

        // Insert one 'analyzing' entry also due now
        _ = try repo.insertCapture(
            Entry(rawText: "pending", type: "word", language: "en", capturedAt: now,
                  aiResult: "{}", analysisState: AnalysisState.analyzing.rawValue),
            dueDate: now.addingTimeInterval(-1))

        let review = ReviewRepository(dbQueue: queue)
        let dueCount = try review.dueCount(on: now)
        let dueCardsResult = try review.dueCards(on: now)

        XCTAssertEqual(dueCount, 1, "dueCount should exclude non-ready entries")
        XCTAssertEqual(dueCardsResult.count, 1, "dueCards should exclude non-ready entries")
        XCTAssertEqual(dueCardsResult.first?.entry.rawText, "ephemeral")
    }

    func testBackfillCaptureContextOnlyFillsNulls() throws {
        let q = try VokabDatabase.makeInMemory()
        let repo = EntryRepository(dbQueue: q)
        let entry = Entry(rawText: "grasp", type: CardType.word.rawValue, language: "en",
                          sourceApp: "Safari", sourceURL: nil,
                          capturedAt: Date(timeIntervalSince1970: 1), aiResult: "{}",
                          cefr: nil, category: nil, captureSentence: nil)
        let id = try repo.insertCapture(entry, dueDate: Date(timeIntervalSince1970: 1))

        try repo.backfillCaptureContextIfMissing(
            id: id, captureSentence: "I grasp it.", sourceApp: "Chrome", sourceURL: "http://x")

        let saved = try XCTUnwrap(repo.entry(id: id))
        XCTAssertEqual(saved.captureSentence, "I grasp it.")  // was nil → filled
        XCTAssertEqual(saved.sourceApp, "Safari")             // already set → untouched
        XCTAssertEqual(saved.sourceURL, "http://x")           // was nil → filled
    }
}
