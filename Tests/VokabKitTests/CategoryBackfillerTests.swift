import XCTest
import GRDB
@testable import VokabKit

final class CategoryBackfillerTests: XCTestCase {
    func testBackfillsNullCategoryFromAgy() async throws {
        let queue = try VokabDatabase.makeInMemory()
        let entries = EntryRepository(dbQueue: queue)
        let categories = CategoryService(dbQueue: queue)
        let id = try entries.insertCapture(
            Entry(rawText: "router", type: CardType.word.rawValue, language: "en",
                  capturedAt: Date(), aiResult: "{}"), dueDate: Date())

        let runner = MockAgyRunner(response: #"{"category":"technology"}"#)
        let agy = AgyService(runner: runner, settings: VokabSettings())
        let backfiller = CategoryBackfiller(agy: agy, entries: entries, categories: categories)

        let result = try await backfiller.backfill(entry: entries.entry(id: id)!)
        XCTAssertEqual(result, "Technology")
        XCTAssertEqual(try entries.entry(id: id)?.category, "Technology")
    }

    func testSkipsAlreadyCategorized() async throws {
        let queue = try VokabDatabase.makeInMemory()
        let entries = EntryRepository(dbQueue: queue)
        let categories = CategoryService(dbQueue: queue)
        let id = try entries.insertCapture(
            Entry(rawText: "router", type: CardType.word.rawValue, language: "en",
                  capturedAt: Date(), aiResult: "{}", category: "Science"), dueDate: Date())
        let runner = MockAgyRunner(response: #"{"category":"technology"}"#)
        let backfiller = CategoryBackfiller(
            agy: AgyService(runner: runner, settings: VokabSettings()),
            entries: entries, categories: categories)
        let result = try await backfiller.backfill(entry: entries.entry(id: id)!)
        XCTAssertEqual(result, "Science")   // untouched, no agy call needed
    }
}
