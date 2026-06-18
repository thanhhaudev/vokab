import XCTest
import GRDB
@testable import VokabKit

final class MigrationTests: XCTestCase {

    func testMigrationCreatesAllTables() throws {
        let queue = try VokabDatabase.makeInMemory()
        try queue.read { db in
            for table in ["entries", "review_state", "tags", "cache", "quota_log", "review_log"] {
                XCTAssertTrue(try db.tableExists(table), "missing table \(table)")
            }
        }
    }

    func testIndexesExist() throws {
        let queue = try VokabDatabase.makeInMemory()
        try queue.read { db in
            let indexes = try Row.fetchAll(db, sql: "SELECT name FROM sqlite_master WHERE type='index'")
                .compactMap { $0["name"] as String? }
            // GRDB auto-names indexes created via create(indexOn:).
            let joined = indexes.joined(separator: ",")
            XCTAssertTrue(joined.contains("cefr"), "expected an index on cefr")
            XCTAssertTrue(joined.contains("language"), "expected an index on language")
            XCTAssertTrue(joined.contains("due_date"), "expected an index on due_date")
        }
    }

    func testEnrichedColumnExists() throws {
        let queue = try VokabDatabase.makeInMemory()
        try queue.read { db in
            let cols = try db.columns(in: "entries").map(\.name)
            XCTAssertTrue(cols.contains("enriched"))
        }
    }

    func testV4SeedsElevenCategoriesAndAddsColumn() throws {
        let queue = try VokabDatabase.makeInMemory()
        try queue.read { db in
            XCTAssertTrue(try db.columns(in: "entries").contains { $0.name == "category" })
            let seeds = try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM categories WHERE is_seed = 1") ?? 0
            XCTAssertEqual(seeds, 11)
            let tech = try String.fetchOne(db, sql: "SELECT name FROM categories WHERE normalized_name = 'technology'")
            XCTAssertEqual(tech, "Technology")
        }
    }

    func test_v6_addsAnalysisStateDefaultingReady() throws {
        let queue = try VokabDatabase.makeInMemory()
        try queue.write { db in
            try db.execute(sql: """
                INSERT INTO entries (raw_text, type, language, captured_at, ai_result, enriched, analysis_state)
                VALUES ('x','word','en',?, '{}', 0, 'ready')
                """, arguments: [Date()])
        }
        let state = try queue.read { db in
            try String.fetchOne(db, sql: "SELECT analysis_state FROM entries WHERE raw_text='x'")
        }
        XCTAssertEqual(state, "ready")
    }

    func testInsertAndFetchEntryRoundTrips() throws {
        let queue = try VokabDatabase.makeInMemory()
        var entry = Entry(rawText: "ephemeral", type: CardType.word.rawValue, language: "en",
                          capturedAt: Date(timeIntervalSince1970: 1_700_000_000),
                          aiResult: #"{"pos":"adjective"}"#, cefr: "c1")
        try queue.write { db in try entry.insert(db) }
        XCTAssertNotNil(entry.id)

        let fetched = try queue.read { db in try Entry.fetchOne(db, key: entry.id!) }
        XCTAssertEqual(fetched?.rawText, "ephemeral")
        XCTAssertEqual(fetched?.cefr, "c1")
        XCTAssertEqual(fetched?.cardType, .word)
    }
}
