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
