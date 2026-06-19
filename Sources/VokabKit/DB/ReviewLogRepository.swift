import Foundation
import GRDB

/// Records a per-day review tally and computes the current day-streak.
public struct ReviewLogRepository: Sendable {
    private let dbQueue: DatabaseQueue
    public init(dbQueue: DatabaseQueue) { self.dbQueue = dbQueue }

    /// Records that a review happened on `date` (increments the day's count).
    public func record(on date: Date) throws {
        let day = TextKey.dayString(date)
        try dbQueue.write { db in
            if var row = try ReviewLog.fetchOne(db, key: day) {
                row.count += 1
                try row.update(db)
            } else {
                try ReviewLog(day: day, count: 1).insert(db)
            }
        }
    }

    /// Current streak: consecutive days with ≥1 review, ending today (or
    /// yesterday if nothing has been reviewed yet today).
    public func streak(asOf now: Date = Date(), calendar: Calendar = .current) throws -> Int {
        let days: Set<String> = try dbQueue.read { db in
            Set(try String.fetchAll(db, sql: "SELECT day FROM review_log WHERE count > 0"))
        }
        guard !days.isEmpty else { return 0 }

        var cursor = calendar.startOfDay(for: now)
        // If today has no review yet, anchor on yesterday so an active streak
        // isn't shown as broken until the day actually ends.
        if !days.contains(TextKey.dayString(cursor, calendar: calendar)) {
            cursor = calendar.date(byAdding: .day, value: -1, to: cursor) ?? cursor
        }
        var streak = 0
        while days.contains(TextKey.dayString(cursor, calendar: calendar)) {
            streak += 1
            guard let prev = calendar.date(byAdding: .day, value: -1, to: cursor) else { break }
            cursor = prev
        }
        return streak
    }
}
