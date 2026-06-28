import XCTest
import GRDB
@testable import VokabKit

final class CapturedFormColumnTests: XCTestCase {
    func test_entry_persists_and_reads_capturedForm() throws {
        let queue = try VokabDatabase.makeInMemory()
        let repo = EntryRepository(dbQueue: queue)
        let id = try repo.insertCapture(
            Entry(rawText: "run", type: "word", language: "en",
                  capturedAt: Date(), aiResult: "{}", capturedForm: "running"),
            dueDate: Date())
        XCTAssertEqual(try repo.entry(id: id)?.capturedForm, "running")
    }

    func test_capturedForm_defaultsNil() throws {
        let queue = try VokabDatabase.makeInMemory()
        let repo = EntryRepository(dbQueue: queue)
        let id = try repo.insertCapture(
            Entry(rawText: "run", type: "word", language: "en",
                  capturedAt: Date(), aiResult: "{}"),
            dueDate: Date())
        XCTAssertNil(try repo.entry(id: id)?.capturedForm)
    }
}

final class ResolveHeadwordTests: XCTestCase {
    private func pending(_ repo: EntryRepository, surface: String) throws -> Int64 {
        try repo.insertCapture(
            Entry(rawText: surface, type: "word", language: "en", capturedAt: Date(),
                  aiResult: "{}", analysisState: AnalysisState.analyzing.rawValue),
            dueDate: Date())
    }

    func test_renamesInPlace_whenHeadwordNew() throws {
        let queue = try VokabDatabase.makeInMemory()
        let repo = EntryRepository(dbQueue: queue)
        let id = try pending(repo, surface: "running")
        let res = try repo.resolveHeadwordAndMarkAnalyzed(
            id: id, headword: "run", capturedForm: "running", language: "en",
            aiResult: #"{"headword":"run"}"#, cefr: "a2", frequency: nil, category: nil,
            captureSentence: nil, sourceApp: nil, sourceURL: nil)
        XCTAssertEqual(res, .renamedInPlace)
        let e = try XCTUnwrap(repo.entry(id: id))
        XCTAssertEqual(e.rawText, "run")
        XCTAssertEqual(e.normalizedText, "run")
        XCTAssertEqual(e.capturedForm, "running")
        XCTAssertEqual(e.analysisState, AnalysisState.ready.rawValue)
        XCTAssertEqual(e.cefr, "a2")
    }

    func test_mergesIntoExisting_andDeletesPending() throws {
        let queue = try VokabDatabase.makeInMemory()
        let repo = EntryRepository(dbQueue: queue)
        let existing = try repo.insertCapture(
            Entry(rawText: "run", type: "word", language: "en", capturedAt: Date(), aiResult: "{}"),
            dueDate: Date())
        let pendingId = try pending(repo, surface: "ran")
        let res = try repo.resolveHeadwordAndMarkAnalyzed(
            id: pendingId, headword: "run", capturedForm: "ran", language: "en",
            aiResult: #"{"headword":"run"}"#, cefr: nil, frequency: nil, category: nil,
            captureSentence: "We ran fast.", sourceApp: "Safari", sourceURL: nil)
        XCTAssertEqual(res, .mergedInto(existingId: existing))
        XCTAssertNil(try repo.entry(id: pendingId))                 // pending deleted
        XCTAssertEqual(try repo.entry(id: existing)?.captureSentence, "We ran fast.")  // backfilled
        XCTAssertEqual(try repo.all().count, 1)                     // no duplicate
    }

    /// A freshly-analyzed inflection must NOT vanish into a still-failed/empty
    /// lemma row: the survivor is promoted with the new content (its id + review
    /// progress preserved), not left failed.
    func test_mergeIntoFailedExisting_promotesSurvivorWithFreshContent() throws {
        let queue = try VokabDatabase.makeInMemory()
        let repo = EntryRepository(dbQueue: queue)
        let existing = try repo.insertCapture(
            Entry(rawText: "run", type: "word", language: "en", capturedAt: Date(),
                  aiResult: "{}", analysisState: AnalysisState.failed.rawValue),
            dueDate: Date())
        let pendingId = try pending(repo, surface: "ran")
        let res = try repo.resolveHeadwordAndMarkAnalyzed(
            id: pendingId, headword: "run", capturedForm: "ran", language: "en",
            aiResult: #"{"headword":"run","senses":[{"pos":"verb"}]}"#, cefr: "a1", frequency: nil,
            category: nil, captureSentence: nil, sourceApp: nil, sourceURL: nil)
        XCTAssertEqual(res, .mergedInto(existingId: existing))      // existing id preserved (keeps review progress)
        XCTAssertNil(try repo.entry(id: pendingId))                // our pending deleted
        let survivor = try XCTUnwrap(repo.entry(id: existing))
        XCTAssertEqual(survivor.analysisState, AnalysisState.ready.rawValue)  // promoted, not left failed
        XCTAssertTrue(survivor.aiResult.contains("senses"))        // filled with the fresh analysis
        XCTAssertEqual(survivor.cefr, "a1")
        XCTAssertEqual(try repo.all().count, 1)
    }

    /// Same promotion when the existing lemma row is still mid-analysis.
    func test_mergeIntoAnalyzingExisting_promotesSurvivor() throws {
        let queue = try VokabDatabase.makeInMemory()
        let repo = EntryRepository(dbQueue: queue)
        let existing = try repo.insertCapture(
            Entry(rawText: "run", type: "word", language: "en", capturedAt: Date(),
                  aiResult: "{}", analysisState: AnalysisState.analyzing.rawValue),
            dueDate: Date())
        let pendingId = try pending(repo, surface: "ran")
        _ = try repo.resolveHeadwordAndMarkAnalyzed(
            id: pendingId, headword: "run", capturedForm: "ran", language: "en",
            aiResult: #"{"headword":"run","senses":[{"pos":"verb"}]}"#, cefr: nil, frequency: nil,
            category: nil, captureSentence: nil, sourceApp: nil, sourceURL: nil)
        let survivor = try XCTUnwrap(repo.entry(id: existing))
        XCTAssertEqual(survivor.analysisState, AnalysisState.ready.rawValue)
        XCTAssertTrue(survivor.aiResult.contains("senses"))
    }

    /// A READY lemma card already has good content — merging an inflection into it
    /// must NOT clobber that content with the inflection's fresh result.
    func test_mergeIntoReadyExisting_doesNotClobberContent() throws {
        let queue = try VokabDatabase.makeInMemory()
        let repo = EntryRepository(dbQueue: queue)
        let existing = try repo.insertCapture(
            Entry(rawText: "run", type: "word", language: "en", capturedAt: Date(),
                  aiResult: #"{"headword":"run","ipa":"keep"}"#, analysisState: AnalysisState.ready.rawValue),
            dueDate: Date())
        let pendingId = try pending(repo, surface: "ran")
        _ = try repo.resolveHeadwordAndMarkAnalyzed(
            id: pendingId, headword: "run", capturedForm: "ran", language: "en",
            aiResult: #"{"headword":"run","ipa":"CLOBBER"}"#, cefr: nil, frequency: nil,
            category: nil, captureSentence: nil, sourceApp: nil, sourceURL: nil)
        let survivor = try XCTUnwrap(repo.entry(id: existing))
        XCTAssertTrue(survivor.aiResult.contains("keep"))          // existing content preserved
        XCTAssertFalse(survivor.aiResult.contains("CLOBBER"))      // ours did not overwrite it
    }

    func test_addAlias_findByAlias_roundtrip() throws {
        let queue = try VokabDatabase.makeInMemory()
        let repo = EntryRepository(dbQueue: queue)
        let id = try repo.insertCapture(
            Entry(rawText: "run", type: "word", language: "en", capturedAt: Date(), aiResult: "{}"),
            dueDate: Date())
        try repo.addAlias(entryId: id, surface: "Running", language: "en")
        XCTAssertEqual(try repo.findByAlias("running", language: "en")?.rawText, "run")
        XCTAssertNil(try repo.findByAlias("walking", language: "en"))
    }

    func test_delete_removesAliases() throws {
        let queue = try VokabDatabase.makeInMemory()
        let repo = EntryRepository(dbQueue: queue)
        let id = try repo.insertCapture(
            Entry(rawText: "run", type: "word", language: "en", capturedAt: Date(), aiResult: "{}"),
            dueDate: Date())
        try repo.addAlias(entryId: id, surface: "ran", language: "en")
        try repo.delete(id: id)
        XCTAssertNil(try repo.findByAlias("ran", language: "en"))   // alias gone with the entry
    }

    /// Rename records the captured surface as an alias.
    func test_rename_recordsAlias() throws {
        let queue = try VokabDatabase.makeInMemory()
        let repo = EntryRepository(dbQueue: queue)
        let id = try pending(repo, surface: "running")
        _ = try repo.resolveHeadwordAndMarkAnalyzed(
            id: id, headword: "run", capturedForm: "running", language: "en",
            aiResult: #"{"headword":"run"}"#, cefr: nil, frequency: nil, category: nil,
            captureSentence: nil, sourceApp: nil, sourceURL: nil)
        XCTAssertEqual(try repo.findByAlias("running", language: "en")?.id, id)
    }

    /// Codex finding 1: merging an inflection into an existing lemma must record the
    /// merged surface as an alias on the survivor, so re-capturing it dedupes.
    /// Codex finding: an inflection-merge promotes a still-analyzing lemma to ready;
    /// the lemma's OWN late failure must NOT clobber it back to failed.
    func test_markAnalysisFailed_doesNotClobberPromotedReady() throws {
        let queue = try VokabDatabase.makeInMemory()
        let repo = EntryRepository(dbQueue: queue)
        // A: lemma "run" still analyzing (its worker is in flight).
        let a = try repo.insertCapture(
            Entry(rawText: "run", type: "word", language: "en", capturedAt: Date(),
                  aiResult: "{}", analysisState: AnalysisState.analyzing.rawValue), dueDate: Date())
        // B: inflection "ran" finishes first → promotes A to ready with content, deletes B.
        let b = try pending(repo, surface: "ran")
        _ = try repo.resolveHeadwordAndMarkAnalyzed(
            id: b, headword: "run", capturedForm: "ran", language: "en",
            aiResult: #"{"headword":"run","senses":[{"pos":"verb"}]}"#, cefr: nil, frequency: nil,
            category: nil, captureSentence: nil, sourceApp: nil, sourceURL: nil)
        XCTAssertEqual(try repo.entry(id: a)?.analysisState, AnalysisState.ready.rawValue)  // promoted
        // A's own worker fails LATE.
        let didFail = try repo.markAnalysisFailed(id: a)
        XCTAssertFalse(didFail)                                                            // CAS: no transition
        XCTAssertEqual(try repo.entry(id: a)?.analysisState, AnalysisState.ready.rawValue) // still ready
        XCTAssertTrue(try XCTUnwrap(repo.entry(id: a)).aiResult.contains("senses"))        // content intact
    }

    func test_markAnalysisFailed_appliesWhenStillAnalyzing() throws {
        let queue = try VokabDatabase.makeInMemory()
        let repo = EntryRepository(dbQueue: queue)
        let id = try pending(repo, surface: "stubborn")
        XCTAssertTrue(try repo.markAnalysisFailed(id: id))
        XCTAssertEqual(try repo.entry(id: id)?.analysisState, AnalysisState.failed.rawValue)
    }

    func test_merge_recordsAliasOnSurvivor() throws {
        let queue = try VokabDatabase.makeInMemory()
        let repo = EntryRepository(dbQueue: queue)
        let existing = try repo.insertCapture(
            Entry(rawText: "run", type: "word", language: "en", capturedAt: Date(),
                  aiResult: "{}", analysisState: AnalysisState.ready.rawValue),
            dueDate: Date())
        let pendingId = try pending(repo, surface: "ran")
        let res = try repo.resolveHeadwordAndMarkAnalyzed(
            id: pendingId, headword: "run", capturedForm: "ran", language: "en",
            aiResult: #"{"headword":"run"}"#, cefr: nil, frequency: nil, category: nil,
            captureSentence: nil, sourceApp: nil, sourceURL: nil)
        XCTAssertEqual(res, .mergedInto(existingId: existing))
        XCTAssertEqual(try repo.findByAlias("ran", language: "en")?.id, existing)   // alias → survivor
    }

    func test_seedAliases_makesEachFormDedupe() throws {
        let queue = try VokabDatabase.makeInMemory()
        let repo = EntryRepository(dbQueue: queue)
        let id = try repo.insertCapture(
            Entry(rawText: "run", type: "word", language: "en", capturedAt: Date(), aiResult: "{}"),
            dueDate: Date())
        try repo.seedAliases(entryId: id, forms: [
            WordForm(label: "past", form: "ran"),
            WordForm(label: "-ing", form: "running"),
        ], language: "en")
        XCTAssertEqual(try repo.findByAlias("ran", language: "en")?.id, id)
        XCTAssertEqual(try repo.findByAlias("running", language: "en")?.id, id)
        // Idempotent re-seed must not throw on the unique index.
        XCTAssertNoThrow(try repo.seedAliases(entryId: id, forms: [WordForm(label: "past", form: "ran")], language: "en"))
    }
}
