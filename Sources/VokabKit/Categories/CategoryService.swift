import Foundation
import GRDB

/// Reads the category taxonomy and canonicalizes agy-proposed categories.
///
/// Dedup is **normalized-exact** (lower+trim+collapse via `TextKey.normalize`),
/// never fuzzy — "Health" and "Wealth" must stay distinct. A proposal that does
/// not match an existing row creates a new canonical category with a deterministic
/// color so the sidebar stays stable (SPEC §7, Phase 2).
public struct CategoryService: Sendable {
    /// Number of distinct colors in the UI palette (App maps `colorIndex` → Color).
    public static let paletteSize = 12

    private let dbQueue: DatabaseQueue
    public init(dbQueue: DatabaseQueue) { self.dbQueue = dbQueue }

    /// Existing category names: seeds first, then user/agy-created by creation time.
    public func currentTaxonomy() throws -> [String] {
        try dbQueue.read { db in
            try Category
                .order(Column("is_seed").desc, Column("created_at").asc, Column("name").asc)
                .fetchAll(db)
                .map(\.name)
        }
    }

    /// Maps an agy-proposed (or user-typed) category to a canonical name, creating
    /// it if new. Returns nil for nil/blank input (entry stays unclassified).
    @discardableResult
    public func canonicalize(_ raw: String?, now: Date = Date()) throws -> String? {
        guard let raw else { return nil }
        let display = CategoryName.prettify(raw)
        guard !display.isEmpty else { return nil }
        let normalized = TextKey.normalize(display)

        return try dbQueue.write { db in
            if let existing = try Category
                .filter(Column("normalized_name") == normalized).fetchOne(db) {
                return existing.name
            }
            // INSERT OR IGNORE + UNIQUE(normalized_name) makes concurrent proposals
            // of the same name converge on one row; read back the winner.
            try db.execute(sql: """
                INSERT OR IGNORE INTO categories
                    (name, normalized_name, color_index, is_seed, created_at)
                VALUES (?, ?, ?, 0, ?)
                """, arguments: [display, normalized,
                                 Self.stableColorIndex(normalized), now])
            return try Category
                .filter(Column("normalized_name") == normalized).fetchOne(db)?.name ?? display
        }
    }

    /// Một lần: đổi `name` các category sang dạng prettify (giữ normalized_name +
    /// color + dedup). Trả số row đã đổi. Idempotent.
    @discardableResult
    public func prettifyExistingNames() throws -> Int {
        try dbQueue.write { db in
            var changed = 0
            let cats = try Category.fetchAll(db)
            for c in cats {
                let pretty = CategoryName.prettify(c.name)
                guard !pretty.isEmpty, pretty != c.name else { continue }
                let newNorm = TextKey.normalize(pretty)
                // Nếu đã tồn tại row khác với normalized mới → đây là trùng:
                // dồn entries sang row đó, xoá row snake này.
                if newNorm != c.normalizedName,
                   let other = try Category.filter(Column("normalized_name") == newNorm).fetchOne(db),
                   other.name != c.name {
                    try db.execute(sql: "UPDATE entries SET category = ? WHERE category = ?",
                                   arguments: [other.name, c.name])
                    try db.execute(sql: "DELETE FROM categories WHERE name = ?", arguments: [c.name])
                    changed += 1
                    continue
                }
                try db.execute(sql: "UPDATE categories SET name = ?, normalized_name = ? WHERE name = ?",
                               arguments: [pretty, newNorm, c.name])
                try db.execute(sql: "UPDATE entries SET category = ? WHERE category = ?",
                               arguments: [pretty, c.name])
                changed += 1
            }
            return changed
        }
    }

    /// Deterministic FNV-1a hash → palette index. MUST NOT use Swift's `Hasher`
    /// (per-process randomized → flaky colors/tests).
    public static func stableColorIndex(_ s: String) -> Int {
        var hash: UInt32 = 2166136261
        for byte in s.utf8 { hash = (hash ^ UInt32(byte)) &* 16777619 }
        return Int(hash % UInt32(paletteSize))
    }
}
