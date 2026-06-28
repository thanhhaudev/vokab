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
}
