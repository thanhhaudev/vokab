import Foundation
import GRDB

/// Factory + schema for the vokab SQLite database (GRDB).
public enum VokabDatabase {

    /// Opens (creating if needed) a database at `path` and runs migrations.
    public static func makeQueue(path: String) throws -> DatabaseQueue {
        let queue = try DatabaseQueue(path: path)
        try migrator.migrate(queue)
        return queue
    }

    /// An in-memory database (tests). Migrated and ready to use.
    public static func makeInMemory() throws -> DatabaseQueue {
        let queue = try DatabaseQueue()
        try migrator.migrate(queue)
        return queue
    }

    /// Default on-disk location under Application Support.
    public static func defaultPath() throws -> String {
        let fm = FileManager.default
        let dir = try fm.url(for: .applicationSupportDirectory, in: .userDomainMask,
                             appropriateFor: nil, create: true)
            .appendingPathComponent("vokab", isDirectory: true)
        try fm.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("vokab.sqlite").path
    }

    public static var migrator: DatabaseMigrator {
        var migrator = DatabaseMigrator()

        migrator.registerMigration("v1") { db in
            try db.create(table: "entries") { t in
                t.autoIncrementedPrimaryKey("id")
                t.column("raw_text", .text).notNull()
                t.column("type", .text).notNull()
                t.column("language", .text).notNull()
                t.column("source_app", .text)
                t.column("source_url", .text)
                t.column("captured_at", .datetime).notNull()
                t.column("ai_result", .text).notNull()
                t.column("cefr", .text)
                t.column("frequency", .text)
            }
            try db.create(indexOn: "entries", columns: ["cefr"])
            try db.create(indexOn: "entries", columns: ["language"])

            try db.create(table: "review_state") { t in
                t.primaryKey("entry_id", .integer)
                    .references("entries", onDelete: .cascade)
                t.column("ease_factor", .double).notNull().defaults(to: 2.5)
                t.column("interval", .integer).notNull().defaults(to: 0)
                t.column("due_date", .datetime).notNull()
                t.column("review_count", .integer).notNull().defaults(to: 0)
                t.column("last_review", .datetime)
                t.column("card_mode", .text).notNull().defaults(to: "recognition")
            }
            try db.create(indexOn: "review_state", columns: ["due_date"])

            try db.create(table: "tags") { t in
                t.column("entry_id", .integer).notNull()
                    .references("entries", onDelete: .cascade)
                t.column("tag", .text).notNull()
            }
            try db.create(indexOn: "tags", columns: ["entry_id"])

            try db.create(table: "cache") { t in
                t.primaryKey("key", .text)
                t.column("ai_result", .text).notNull()
                t.column("created_at", .datetime).notNull()
            }

            try db.create(table: "quota_log") { t in
                t.primaryKey("day", .text)
                t.column("call_count", .integer).notNull().defaults(to: 0)
                t.column("token_estimate", .integer).notNull().defaults(to: 0)
            }
        }

        migrator.registerMigration("v2_review_log") { db in
            try db.create(table: "review_log") { t in
                t.primaryKey("day", .text)
                t.column("count", .integer).notNull().defaults(to: 0)
            }
        }

        migrator.registerMigration("v3_enriched") { db in
            try db.alter(table: "entries") { t in
                t.add(column: "enriched", .boolean).notNull().defaults(to: false)
            }
        }

        migrator.registerMigration("v4_categories") { db in
            try db.alter(table: "entries") { t in
                t.add(column: "category", .text)        // NULL = unclassified (Phase-1 entries)
            }
            try db.create(indexOn: "entries", columns: ["category"])

            try db.create(table: "categories") { t in
                t.primaryKey("name", .text)
                t.column("normalized_name", .text).notNull().unique()
                t.column("color_index", .integer).notNull()
                t.column("is_seed", .boolean).notNull().defaults(to: false)
                t.column("created_at", .datetime).notNull()
            }

            let seeds = ["Academic", "Business", "Daily life", "Technology", "Science",
                         "Arts & Culture", "News & Politics", "Travel", "Health",
                         "Slang & Informal", "Idioms & Expressions"]
            let now = Date()
            for (i, name) in seeds.enumerated() {
                try db.execute(sql: """
                    INSERT INTO categories (name, normalized_name, color_index, is_seed, created_at)
                    VALUES (?, ?, ?, 1, ?)
                    """, arguments: [name, TextKey.normalize(name), i % CategoryService.paletteSize, now])
            }
        }

        migrator.registerMigration("v5_capture_sentence") { db in
            try db.alter(table: "entries") { t in
                t.add(column: "capture_sentence", .text)   // NULL for pre-E + contextless captures
            }
        }

        migrator.registerMigration("v6_analysis_state") { db in
            try db.alter(table: "entries") { t in
                t.add(column: "analysis_state", .text).notNull().defaults(to: "ready")
            }
            try db.create(indexOn: "entries", columns: ["analysis_state"])
        }

        // DB-level dedup guard (SPEC §11). Mirrors `EntryRepository.find` /
        // `insertCapture`, which key on `lower(trim(raw_text))` + `lower(language)`,
        // so a concurrent capture of the same term can't create a duplicate row.
        migrator.registerMigration("v7_dedup_unique") { db in
            // Collapse any pre-existing duplicates before adding the unique index.
            // Keep the BEST row per normalized key rather than blindly the earliest,
            // so irreplaceable data survives: most-reviewed first (learning progress
            // can't be re-derived), then enriched, then earliest id. Done with plain
            // SQL — not FK cascade — so orphan cleanup doesn't depend on the
            // foreign-keys pragma being on during migration.
            try db.execute(sql: """
                DELETE FROM entries WHERE id IN (
                    SELECT id FROM (
                        SELECT e.id,
                               ROW_NUMBER() OVER (
                                   PARTITION BY lower(trim(e.raw_text)), lower(e.language)
                                   ORDER BY COALESCE(rs.review_count, 0) DESC, e.enriched DESC, e.id ASC
                               ) AS rn
                        FROM entries e
                        LEFT JOIN review_state rs ON rs.entry_id = e.id
                    )
                    WHERE rn > 1
                )
                """)
            try db.execute(sql: "DELETE FROM review_state WHERE entry_id NOT IN (SELECT id FROM entries)")
            try db.execute(sql: "DELETE FROM tags WHERE entry_id NOT IN (SELECT id FROM entries)")
            try db.execute(sql: """
                CREATE UNIQUE INDEX idx_entries_dedup
                ON entries (lower(trim(raw_text)), lower(language))
                """)
        }

        // Canonical dedup key. `lower(trim(raw_text))` (v7) only lower-cases and
        // trims edge whitespace, so it doesn't mirror `TextKey.normalize` (which also
        // strips punctuation and collapses inner whitespace). Store the real
        // normalized key in a column and index THAT so the DB guard matches the
        // canonical key exactly. SQLite can't compute `TextKey.normalize`, so backfill
        // is done here in Swift.
        migrator.registerMigration("v8_normalized_text") { db in
            try db.alter(table: "entries") { t in
                t.add(column: "normalized_text", .text)
            }
            // Backfill from existing raw_text using the canonical normalizer.
            let rows = try Row.fetchAll(db, sql: "SELECT id, raw_text FROM entries")
            for row in rows {
                let id: Int64 = row["id"]
                let raw: String = row["raw_text"]
                try db.execute(sql: "UPDATE entries SET normalized_text = ? WHERE id = ?",
                               arguments: [TextKey.normalize(raw), id])
            }
            // The canonical key is stricter than v7's (e.g. "Apple," and "Apple" now
            // collide), so re-collapse any duplicates it exposes — keep the best row
            // (most-reviewed, then enriched, then earliest), same policy as v7.
            try db.execute(sql: """
                DELETE FROM entries WHERE id IN (
                    SELECT id FROM (
                        SELECT e.id,
                               ROW_NUMBER() OVER (
                                   PARTITION BY e.normalized_text, lower(e.language)
                                   ORDER BY COALESCE(rs.review_count, 0) DESC, e.enriched DESC, e.id ASC
                               ) AS rn
                        FROM entries e
                        LEFT JOIN review_state rs ON rs.entry_id = e.id
                    )
                    WHERE rn > 1
                )
                """)
            try db.execute(sql: "DELETE FROM review_state WHERE entry_id NOT IN (SELECT id FROM entries)")
            try db.execute(sql: "DELETE FROM tags WHERE entry_id NOT IN (SELECT id FROM entries)")
            // Add the canonical-key index. The v7 `lower(trim(raw_text))` index is
            // KEPT as a self-maintaining backstop: it's computed from raw_text, so it
            // still catches exact-text duplicates even if a row's normalized_text is
            // NULL (a raw insert that bypasses EntryRepository). It can never falsely
            // reject, because equal lower(trim(raw_text)) implies equal normalized_text.
            try db.execute(sql: """
                CREATE UNIQUE INDEX idx_entries_dedup_norm
                ON entries (normalized_text, lower(language))
                """)
        }

        return migrator
    }
}
