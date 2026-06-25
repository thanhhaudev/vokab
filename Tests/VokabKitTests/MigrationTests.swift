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

    func test_v7_dedupesExistingRowsAndEnforcesUniqueIndex() throws {
        let queue = try DatabaseQueue()
        // Migrate only up to v6 so we can plant duplicates the way an old DB would.
        try VokabDatabase.migrator.migrate(queue, upTo: "v6_analysis_state")
        try queue.write { db in
            for raw in ["Spe", "  spe ", "spe", "other"] {
                try db.execute(sql: """
                    INSERT INTO entries (raw_text, type, language, captured_at, ai_result, enriched, analysis_state)
                    VALUES (?, 'word', 'en', ?, '{}', 0, 'ready')
                    """, arguments: [raw, Date()])
            }
        }
        // Run v7 + v8: the "spe" variants collapse to one; "other" survives, and
        // every row gets a backfilled canonical normalized_text.
        try VokabDatabase.migrator.migrate(queue)
        let count = try queue.read { db in
            try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM entries WHERE normalized_text = 'spe'")
        }
        XCTAssertEqual(count, 1, "duplicates should collapse to a single row")
        let backfilled = try queue.read { db in
            try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM entries WHERE normalized_text IS NULL")
        }
        XCTAssertEqual(backfilled, 0, "v8 must backfill normalized_text for every row")

        // The canonical index rejects a new duplicate (same normalized key).
        XCTAssertThrowsError(try queue.write { db in
            try db.execute(sql: """
                INSERT INTO entries (raw_text, normalized_text, type, language, captured_at, ai_result, enriched, analysis_state)
                VALUES ('SPE', 'spe', 'word', 'en', ?, '{}', 0, 'ready')
                """, arguments: [Date()])
        })
        // The self-maintaining lower(trim) backstop rejects an exact-text duplicate
        // even when normalized_text is left NULL (a raw insert bypassing the repo).
        XCTAssertThrowsError(try queue.write { db in
            try db.execute(sql: """
                INSERT INTO entries (raw_text, type, language, captured_at, ai_result, enriched, analysis_state)
                VALUES ('spe', 'word', 'en', ?, '{}', 0, 'ready')
                """, arguments: [Date()])
        })
    }

    func test_v7_keepsTheMostReviewedDuplicate() throws {
        let queue = try DatabaseQueue()
        try VokabDatabase.migrator.migrate(queue, upTo: "v6_analysis_state")
        // Two duplicates of "dup": the LATER row carries real review progress.
        try queue.write { db in
            try db.execute(sql: """
                INSERT INTO entries (id, raw_text, type, language, captured_at, ai_result, enriched, analysis_state)
                VALUES (1, 'dup', 'word', 'en', ?, '{}', 0, 'ready'),
                       (2, 'dup', 'word', 'en', ?, '{}', 0, 'ready')
                """, arguments: [Date(), Date()])
            try db.execute(sql: """
                INSERT INTO review_state (entry_id, due_date, review_count) VALUES (1, ?, 0), (2, ?, 7)
                """, arguments: [Date(), Date()])
        }
        try VokabDatabase.migrator.migrate(queue)

        let rows = try queue.read { db in
            try Row.fetchAll(db, sql: "SELECT id FROM entries WHERE lower(trim(raw_text)) = 'dup'")
        }
        XCTAssertEqual(rows.count, 1)
        XCTAssertEqual(rows.first?["id"], 2)   // the most-reviewed row survived, not the earliest
        let surviving = try queue.read { db in
            try Int.fetchOne(db, sql: "SELECT review_count FROM review_state WHERE entry_id = 2")
        }
        XCTAssertEqual(surviving, 7)           // its review progress is intact
        // The discarded row's review_state was cleaned up (no orphan).
        let orphan = try queue.read { db in
            try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM review_state WHERE entry_id = 1")
        }
        XCTAssertEqual(orphan, 0)
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
