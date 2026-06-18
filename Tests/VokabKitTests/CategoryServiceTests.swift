import XCTest
import GRDB
@testable import VokabKit

final class CategoryServiceTests: XCTestCase {
    private func makeService() throws -> (CategoryService, DatabaseQueue) {
        let queue = try VokabDatabase.makeInMemory()
        return (CategoryService(dbQueue: queue), queue)
    }

    func testReusesExistingSeedCaseInsensitively() throws {
        let (svc, _) = try makeService()
        XCTAssertEqual(try svc.canonicalize("technology"), "Technology")
        XCTAssertEqual(try svc.canonicalize("  TECHNOLOGY  "), "Technology")
    }

    func testCreatesNewCategoryWithStableColor() throws {
        let (svc, queue) = try makeService()
        let name = try svc.canonicalize("Cooking")
        XCTAssertEqual(name, "Cooking")
        let count = try queue.read { try Int.fetchOne($0, sql:
            "SELECT COUNT(*) FROM categories WHERE normalized_name = 'cooking'") } ?? 0
        XCTAssertEqual(count, 1)
        // Deterministic: same input → same color whether stored or recomputed.
        XCTAssertEqual(CategoryService.stableColorIndex("cooking"),
                       CategoryService.stableColorIndex("cooking"))
    }

    func testCanonicalizeIsIdempotentNoDuplicateRows() throws {
        let (svc, queue) = try makeService()
        _ = try svc.canonicalize("Cooking")
        _ = try svc.canonicalize("cooking")
        _ = try svc.canonicalize("COOKING ")
        let rows = try queue.read { try Int.fetchOne($0, sql:
            "SELECT COUNT(*) FROM categories WHERE normalized_name = 'cooking'") } ?? 0
        XCTAssertEqual(rows, 1)
    }

    func testNilAndEmptyReturnNil() throws {
        let (svc, _) = try makeService()
        XCTAssertNil(try svc.canonicalize(nil))
        XCTAssertNil(try svc.canonicalize("   "))
    }

    func testCurrentTaxonomyListsSeeds() throws {
        let (svc, _) = try makeService()
        let taxonomy = try svc.currentTaxonomy()
        XCTAssertEqual(taxonomy.count, 11)
        XCTAssertTrue(taxonomy.contains("Technology"))
    }

    func test_canonicalize_prettifiesSnakeCaseDisplay() throws {
        let queue = try VokabDatabase.makeInMemory()
        let svc = CategoryService(dbQueue: queue)
        let name = try svc.canonicalize("social_media")
        XCTAssertEqual(name, "Social media")
        let again = try svc.canonicalize("Social Media")   // same normalized → same row
        XCTAssertEqual(again, "Social media")
    }

    func test_prettifyExistingNames_fixesOldSnakeCaseRows() throws {
        let queue = try VokabDatabase.makeInMemory()
        try queue.write { db in
            try db.execute(sql: """
                INSERT INTO categories (name, normalized_name, color_index, is_seed, created_at)
                VALUES ('social_media', ?, 3, 0, ?)
                """, arguments: [TextKey.normalize("social_media"), Date()])
        }
        let svc = CategoryService(dbQueue: queue)
        let changed = try svc.prettifyExistingNames()
        XCTAssertEqual(changed, 1)
        let names = try svc.currentTaxonomy()
        XCTAssertTrue(names.contains("Social media"))
        XCTAssertFalse(names.contains("social_media"))
    }

    func test_backfill_thenCanonicalize_noDuplicateRow() throws {
        let queue = try VokabDatabase.makeInMemory()
        try queue.write { db in
            try db.execute(sql: """
                INSERT INTO categories (name, normalized_name, color_index, is_seed, created_at)
                VALUES ('social_media', ?, 3, 0, ?)
                """, arguments: [TextKey.normalize("social_media"), Date()])
        }
        let svc = CategoryService(dbQueue: queue)
        _ = try svc.prettifyExistingNames()
        // Sau backfill, canonicalize dạng Title Case phải trả về CÙNG row, không tạo trùng.
        XCTAssertEqual(try svc.canonicalize("Social media"), "Social media")
        let rows = try queue.read { db in
            try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM categories WHERE name = 'Social media'") ?? 0
        }
        XCTAssertEqual(rows, 1)
    }
}
