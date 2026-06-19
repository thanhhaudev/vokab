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
            let rows = try Row.fetchAll(db, sql: """
                SELECT review_state.*, entries.id AS e_id
                FROM review_state
                JOIN entries ON entries.id = review_state.entry_id
                WHERE review_state.due_date <= ?
                  AND entries.analysis_state = 'ready'
                ORDER BY review_state.due_date ASC
                """, arguments: [date])
            var cards: [ReviewCard] = []
            for row in rows {
                let entryId: Int64 = row["e_id"]
                if let entry = try Entry.fetchOne(db, key: entryId),
                   let state = try ReviewState.fetchOne(db, key: entryId) {
                    cards.append(ReviewCard(entry: entry, state: state))
                }
            }
            return cards
        }
    }

    /// Every card with a review state, soonest-due first. Used for study-ahead
    /// review when nothing is currently due.
    /// Only entries with `analysis_state = 'ready'` are included.
    public func allCards() throws -> [ReviewCard] {
        try dbQueue.read { db in
            let rows = try Row.fetchAll(db, sql: """
                SELECT review_state.*, entries.id AS e_id
                FROM review_state
                JOIN entries ON entries.id = review_state.entry_id
                WHERE entries.analysis_state = 'ready'
                ORDER BY review_state.due_date ASC
                """)
            var cards: [ReviewCard] = []
            for row in rows {
                let entryId: Int64 = row["e_id"]
                if let entry = try Entry.fetchOne(db, key: entryId),
                   let state = try ReviewState.fetchOne(db, key: entryId) {
                    cards.append(ReviewCard(entry: entry, state: state))
                }
            }
            return cards
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

    /// offset-in-days (0 ..< days) → number of cards whose due_date falls on that
    /// calendar day, counting from startOfDay(now). Overdue (< today) folds into 0.
    public func dueForecast(days: Int, asOf now: Date = Date(), calendar: Calendar = .current) throws -> [Int: Int] {
        let dueDates: [Date] = try dbQueue.read { db in
            try Date.fetchAll(db, sql: "SELECT due_date FROM review_state")
        }
        let start = calendar.startOfDay(for: now)
        var result: [Int: Int] = [:]
        for due in dueDates {
            let d = calendar.dateComponents([.day], from: start, to: calendar.startOfDay(for: due)).day ?? 0
            let bucket = max(0, d)
            if bucket < days { result[bucket, default: 0] += 1 }
        }
        return result
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
