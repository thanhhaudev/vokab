import Foundation
import GRDB

/// Reads due cards and persists updated review state.
public struct ReviewRepository: Sendable {
    private let dbQueue: DatabaseQueue
    public init(dbQueue: DatabaseQueue) { self.dbQueue = dbQueue }

    /// Cards whose `due_date` is on or before `date`, soonest first.
    /// Only entries with `analysis_state = 'ready'` are included.
    public func dueCards(on date: Date) throws -> [ReviewCard] {
        try dbQueue.read { db in
            // One query: `entries` and `review_state` columns don't collide, so each
            // record decodes its own columns straight from the joined row (no N+1).
            let rows = try Row.fetchAll(db, sql: """
                SELECT entries.*, review_state.*
                FROM review_state
                JOIN entries ON entries.id = review_state.entry_id
                WHERE review_state.due_date <= ?
                  AND entries.analysis_state = 'ready'
                ORDER BY review_state.due_date ASC
                """, arguments: [date])
            return try rows.map { try ReviewCard(entry: Entry(row: $0), state: ReviewState(row: $0)) }
        }
    }

    /// Every card with a review state, soonest-due first. Used for study-ahead
    /// review when nothing is currently due.
    /// Only entries with `analysis_state = 'ready'` are included.
    public func allCards() throws -> [ReviewCard] {
        try dbQueue.read { db in
            let rows = try Row.fetchAll(db, sql: """
                SELECT entries.*, review_state.*
                FROM review_state
                JOIN entries ON entries.id = review_state.entry_id
                WHERE entries.analysis_state = 'ready'
                ORDER BY review_state.due_date ASC
                """)
            return try rows.map { try ReviewCard(entry: Entry(row: $0), state: ReviewState(row: $0)) }
        }
    }

    public func state(entryId: Int64) throws -> ReviewState? {
        try dbQueue.read { db in try ReviewState.fetchOne(db, key: entryId) }
    }

    /// All review states keyed by entry id, in a single read (avoids N+1 lookups
    /// when the Library loads).
    public func allStates() throws -> [Int64: ReviewState] {
        try dbQueue.read { db in
            let states = try ReviewState.fetchAll(db)
            return Dictionary(states.map { ($0.entryId, $0) }, uniquingKeysWith: { a, _ in a })
        }
    }

    public func update(_ state: ReviewState) throws {
        try dbQueue.write { db in try state.update(db) }
    }

    /// Count of cards due on or before `date`.
    /// Only entries with `analysis_state = 'ready'` are counted.
    public func dueCount(on date: Date) throws -> Int {
        try dbQueue.read { db in
            try Int.fetchOne(db, sql: """
                SELECT COUNT(*) FROM review_state
                JOIN entries ON entries.id = review_state.entry_id
                WHERE review_state.due_date <= ?
                  AND entries.analysis_state = 'ready'
                """, arguments: [date]) ?? 0
        }
    }
}
