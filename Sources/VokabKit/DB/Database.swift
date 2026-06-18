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

        return migrator
    }
}
