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

    /// Atomic find-or-create: returns the existing entry's id if one with the same
    /// normalized text + language is already stored, otherwise inserts the entry
    /// plus an initial recognition review_state due at `dueDate`. The whole check
    /// and insert run in one `write` (serialized by GRDB) so two concurrent
    /// captures of the same term can't both insert; the unique index from migration
    /// v7 is the hard backstop. The existence probe mirrors `find` exactly.
    @discardableResult
    public func insertCapture(_ entry: Entry, dueDate: Date, startingEase: Double = 2.5) throws -> Int64 {
        let normalized = TextKey.normalize(entry.rawText)
        return try dbQueue.write { db in
            if let existingId = try Int64.fetchOne(db, sql: """
                SELECT id FROM entries
                WHERE normalized_text = ? AND lower(language) = lower(?)
                """, arguments: [normalized, entry.language]) {
                return existingId
            }
            var e = entry
            e.normalizedText = normalized               // canonical dedup key (backs the unique index)
            try e.insert(db)
            let id = e.id!
            let state = ReviewState(entryId: id, easeFactor: startingEase, dueDate: dueDate, cardMode: .recognition)
            try state.insert(db)
            return id
        }
    }

    /// Dedup lookup by canonical normalized key + language (SPEC §11).
    public func find(rawText: String, language: String) throws -> Entry? {
        let normalized = TextKey.normalize(rawText)
        return try dbQueue.read { db in
            try Entry
                .filter(sql: "normalized_text = ? AND lower(language) = ?",
                        arguments: [normalized, language.lowercased()])
                .fetchOne(db)
        }
    }

    /// Dedup lookup by a recorded captured-surface alias (e.g. "ran" → the "run"
    /// entry). After a word is lemmatized, every surface it was reached by is recorded
    /// in `entry_aliases`, so re-capturing any inflection dedupes without a fresh agy
    /// call — for BOTH the rename and merge-into-existing paths (unlike a single
    /// `captured_form` column, which can't hold multiple aliases or the merge case).
    public func findByAlias(_ surface: String, language: String) throws -> Entry? {
        let key = TextKey.normalize(surface)
        guard !key.isEmpty else { return nil }
        return try dbQueue.read { db in
            try Entry.fetchOne(db, sql: """
                SELECT e.* FROM entries e
                JOIN entry_aliases a ON a.entry_id = e.id
                WHERE a.normalized_surface = ? AND lower(a.language) = lower(?)
                LIMIT 1
                """, arguments: [key, language])
        }
    }

    /// Records a captured SURFACE form as a dedup alias of `entryId`. The normalized
    /// surface maps to at most one entry per language; a surface already aliased
    /// elsewhere is left untouched (`INSERT OR IGNORE`).
    public func addAlias(entryId: Int64, surface: String, language: String) throws {
        let key = TextKey.normalize(surface)
        guard !key.isEmpty else { return }
        try dbQueue.write { db in try Self.insertAlias(db, entryId: entryId, key: key, language: language) }
    }

    /// Shared alias insert — used by `addAlias` and inside
    /// `resolveHeadwordAndMarkAnalyzed`'s write transaction. `key` is already normalized.
    static func insertAlias(_ db: Database, entryId: Int64, key: String, language: String) throws {
        guard !key.isEmpty else { return }
        try db.execute(sql: "INSERT OR IGNORE INTO entry_aliases (entry_id, normalized_surface, language) VALUES (?, ?, ?)",
                       arguments: [entryId, key, language])
    }

    /// Batch dedup lookup: of the given `texts`, returns the set of normalized keys
    /// (`TextKey.normalize`) already stored for `language`. One query instead of N
    /// `find` calls — used by the batch-capture preview to mark already-saved lines.
    /// Matches the canonical key exactly (the `normalized_text` column).
    public func existingNormalizedKeys(in texts: [String], language: String) throws -> Set<String> {
        let keys = Array(Set(texts.map { TextKey.normalize($0) }.filter { !$0.isEmpty }))
        guard !keys.isEmpty else { return [] }
        return try dbQueue.read { db in
            let placeholders = databaseQuestionMarks(count: keys.count)
            let rows = try String.fetchAll(db, sql: """
                SELECT DISTINCT normalized_text FROM entries
                WHERE lower(language) = ? AND normalized_text IN (\(placeholders))
                """, arguments: StatementArguments([language.lowercased()] + keys))
            return Set(rows)
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
        _ = try dbQueue.write { db in
            // Explicit alias cleanup (don't depend on the FK pragma being on).
            try db.execute(sql: "DELETE FROM entry_aliases WHERE entry_id = ?", arguments: [id])
            return try Entry.deleteOne(db, key: id)
        }
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

    /// Outcome of resolving a freshly-analyzed pending word entry to its lemma.
    public enum HeadwordResolution: Sendable, Equatable {
        case renamedInPlace
        case mergedInto(existingId: Int64)
    }

    /// After core analysis yields a `headword` that differs from the pending
    /// entry's surface text, resolve the entry to that lemma. If no other entry
    /// owns the headword, rename this one in place (storing the surface in
    /// `captured_form`) and mark it analyzed. If one already exists, delete this
    /// pending entry and backfill the existing card's capture context — so repeat
    /// inflections collapse onto one card (SPEC §11). One write, so the unique
    /// dedup indexes never see a transient `raw_text` collision.
    @discardableResult
    public func resolveHeadwordAndMarkAnalyzed(
        id: Int64, headword: String, capturedForm: String, language: String,
        aiResult: String, cefr: String?, frequency: String?, category: String?,
        captureSentence: String?, sourceApp: String?, sourceURL: String?
    ) throws -> HeadwordResolution {
        let normalizedHeadword = TextKey.normalize(headword)
        return try dbQueue.write { db in
            if let existing = try Row.fetchOne(db, sql: """
                SELECT id, analysis_state FROM entries
                WHERE normalized_text = ? AND lower(language) = lower(?) AND id <> ?
                """, arguments: [normalizedHeadword, language, id]) {
                let existingId: Int64 = existing["id"]
                let existingReady = (existing["analysis_state"] as String?) == "ready"
                // Fold into the existing lemma card; drop this pending row (cascade
                // removes its review_state). Backfill only NULL context columns.
                if let s = captureSentence {
                    try db.execute(sql: "UPDATE entries SET capture_sentence = ? WHERE id = ? AND capture_sentence IS NULL",
                                   arguments: [s, existingId])
                }
                if let a = sourceApp {
                    try db.execute(sql: "UPDATE entries SET source_app = ? WHERE id = ? AND source_app IS NULL",
                                   arguments: [a, existingId])
                }
                if let u = sourceURL {
                    try db.execute(sql: "UPDATE entries SET source_url = ? WHERE id = ? AND source_url IS NULL",
                                   arguments: [u, existingId])
                }
                // If the existing lemma row is NOT yet ready (still analyzing, or
                // failed with empty content), promote IT with this fresh analysis —
                // preserving its id + review progress — so a successful capture is
                // never discarded into an empty/failed card. A ready row already has
                // good content, so never clobber it. CAS on `<> 'ready'` so a row that
                // became ready mid-write isn't overwritten.
                if !existingReady {
                    try db.execute(sql: """
                        UPDATE entries SET ai_result = ?, cefr = ?, frequency = ?, category = ?, analysis_state = 'ready'
                        WHERE id = ? AND analysis_state <> 'ready'
                        """, arguments: [aiResult, cefr?.lowercased(), frequency, category, existingId])
                }
                try db.execute(sql: "DELETE FROM entries WHERE id = ?", arguments: [id])
                // Record the merged surface as a dedup alias of the survivor, so
                // re-capturing this inflection dedupes (the single captured_form
                // column on the survivor can't, and isn't touched here).
                try Self.insertAlias(db, entryId: existingId, key: TextKey.normalize(capturedForm), language: language)
                return .mergedInto(existingId: existingId)
            }
            // No conflict: rename this entry to the headword and mark it analyzed.
            try db.execute(sql: """
                UPDATE entries
                SET raw_text = ?, normalized_text = ?, captured_form = ?,
                    ai_result = ?, cefr = ?, frequency = ?, category = ?, analysis_state = 'ready'
                WHERE id = ? AND analysis_state = 'analyzing'
                """, arguments: [headword, normalizedHeadword, capturedForm,
                                 aiResult, cefr?.lowercased(), frequency, category, id])
            // Record the captured surface as a dedup alias of the renamed entry.
            try Self.insertAlias(db, entryId: id, key: TextKey.normalize(capturedForm), language: language)
            return .renamedInPlace
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
