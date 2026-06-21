import Foundation
import GRDB

/// A captured entry paired with its review scheduling state.
public struct ReviewCard: Sendable, Equatable {
    public var entry: Entry
    public var state: ReviewState
    public init(entry: Entry, state: ReviewState) {
        self.entry = entry
        self.state = state
    }
}

/// Reads/writes entries and their initial review state.
public struct EntryRepository: Sendable {
    private let dbQueue: DatabaseQueue
    public init(dbQueue: DatabaseQueue) { self.dbQueue = dbQueue }

    /// Inserts an entry and an initial recognition review_state due at `dueDate`.
    /// Returns the new entry id.
    @discardableResult
    public func insertCapture(_ entry: Entry, dueDate: Date, startingEase: Double = 2.5) throws -> Int64 {
        try dbQueue.write { db in
            var e = entry
            try e.insert(db)
            let id = e.id!
            let state = ReviewState(entryId: id, easeFactor: startingEase, dueDate: dueDate, cardMode: .recognition)
            try state.insert(db)
            return id
        }
    }

    /// Dedup lookup by normalized text + language (SPEC §11).
    public func find(rawText: String, language: String) throws -> Entry? {
        let normalized = TextKey.normalize(rawText)
        return try dbQueue.read { db in
            try Entry
                .filter(sql: "lower(trim(raw_text)) = ? AND lower(language) = ?",
                        arguments: [normalized, language.lowercased()])
                .fetchOne(db)
        }
    }

    public func entry(id: Int64) throws -> Entry? {
        try dbQueue.read { db in try Entry.fetchOne(db, key: id) }
    }

    public func all() throws -> [Entry] {
        try dbQueue.read { db in
            try Entry.order(Column("captured_at").desc).fetchAll(db)
        }
    }

    public func delete(id: Int64) throws {
        _ = try dbQueue.write { db in try Entry.deleteOne(db, key: id) }
    }

    /// Sets (or clears) an entry's category. Used by capture, lazy backfill, and
    /// the detail/flashcard override selector.
    public func setCategory(id: Int64, category: String?) throws {
        _ = try dbQueue.write { db in
            try db.execute(sql: "UPDATE entries SET category = ? WHERE id = ?",
                           arguments: [category, id])
        }
    }

    /// Count of entries per non-null category (for the sidebar).
    public func categoryCounts() throws -> [String: Int] {
        try dbQueue.read { db in
            try Row.fetchAll(db, sql: """
                SELECT category AS c, COUNT(*) AS n FROM entries
                WHERE category IS NOT NULL GROUP BY category
                """).reduce(into: [:]) { acc, row in acc[row["c"]] = row["n"] }
        }
    }

    /// Count of entries with no category yet (the sidebar's "Uncategorized" group).
    public func uncategorizedCount() throws -> Int {
        try dbQueue.read { db in
            try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM entries WHERE category IS NULL") ?? 0
        }
    }

    /// Replaces the stored ai_result and marks the entry enriched (tier-2 done).
    /// Compare-and-swap on `enriched = 0` so a concurrent enrichment cannot clobber
    /// an already-enriched row. Returns true if this call performed the update.
    @discardableResult
    public func markEnriched(id: Int64, aiResult: String) throws -> Bool {
        try dbQueue.write { db in
            try db.execute(sql: "UPDATE entries SET ai_result = ?, enriched = 1 WHERE id = ? AND enriched = 0",
                           arguments: [aiResult, id])
            return db.changesCount > 0
        }
    }

    /// Replaces the stored ai_result without touching the `enriched` flag — used
    /// by backfillers that augment an entry that is already enriched.
    public func setAiResult(id: Int64, aiResult: String) throws {
        try dbQueue.write { db in
            try db.execute(sql: "UPDATE entries SET ai_result = ? WHERE id = ?",
                           arguments: [aiResult, id])
        }
    }

    /// Hoàn tất phân tích core: ghi ai_result + denormalized + state=ready.
    /// CAS trên analysis_state='analyzing'. Trả true nếu update.
    @discardableResult
    public func markAnalyzed(id: Int64, aiResult: String, cefr: String?,
                             frequency: String?, category: String?) throws -> Bool {
        try dbQueue.write { db in
            try db.execute(sql: """
                UPDATE entries SET ai_result = ?, cefr = ?, frequency = ?, category = ?, analysis_state = 'ready'
                WHERE id = ? AND analysis_state = 'analyzing'
                """, arguments: [aiResult, cefr?.lowercased(), frequency, category, id])
            return db.changesCount > 0
        }
    }

    public func markAnalysisFailed(id: Int64) throws {
        try dbQueue.write { db in
            try db.execute(sql: "UPDATE entries SET analysis_state = 'failed' WHERE id = ?", arguments: [id])
        }
    }

    /// Đặt lại một entry failed về 'analyzing' để worker chạy lại.
    public func markAnalyzingAgain(id: Int64) throws {
        try dbQueue.write { db in
            try db.execute(sql: "UPDATE entries SET analysis_state = 'analyzing' WHERE id = ?", arguments: [id])
        }
    }

    /// Id các entry đang chờ phân tích core (resume sau relaunch/crash).
    public func pendingEntryIds() throws -> [Int64] {
        try dbQueue.read { db in
            try Int64.fetchAll(db, sql: "SELECT id FROM entries WHERE analysis_state = 'analyzing' ORDER BY captured_at ASC")
        }
    }

    /// Fills capture-context columns that are currently NULL, leaving existing
    /// values intact. Used by the paragraph dedupe guard so re-capturing a word
    /// that's already saved enriches it (e.g. its original sentence) without
    /// clobbering data (SPEC §11, paragraph fixes).
    public func backfillCaptureContextIfMissing(id: Int64, captureSentence: String?,
                                                sourceApp: String?, sourceURL: String?) throws {
        _ = try dbQueue.write { db in
            if let s = captureSentence {
                try db.execute(sql: "UPDATE entries SET capture_sentence = ? WHERE id = ? AND capture_sentence IS NULL",
                               arguments: [s, id])
            }
            if let a = sourceApp {
                try db.execute(sql: "UPDATE entries SET source_app = ? WHERE id = ? AND source_app IS NULL",
                               arguments: [a, id])
            }
            if let u = sourceURL {
                try db.execute(sql: "UPDATE entries SET source_url = ? WHERE id = ? AND source_url IS NULL",
                               arguments: [u, id])
            }
        }
    }
}
