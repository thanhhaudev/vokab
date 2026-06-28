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

    func test_findByCapturedForm_matchesNormalizedSurface() throws {
        let queue = try VokabDatabase.makeInMemory()
        let repo = EntryRepository(dbQueue: queue)
        _ = try repo.insertCapture(
            Entry(rawText: "run", type: "word", language: "en", capturedAt: Date(),
                  aiResult: "{}", capturedForm: "running"),
            dueDate: Date())
        XCTAssertEqual(try repo.findByCapturedForm("Running", language: "en")?.rawText, "run")
        XCTAssertNil(try repo.findByCapturedForm("walking", language: "en"))
    }
}
