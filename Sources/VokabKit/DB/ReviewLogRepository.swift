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

    /// Number of reviews recorded on `date`'s calendar day (0 if none).
    public func count(on date: Date, calendar: Calendar = .current) throws -> Int {
        let day = TextKey.dayString(date, calendar: calendar)
        return try dbQueue.read { db in
            try Int.fetchOne(db, sql: "SELECT count FROM review_log WHERE day = ?", arguments: [day]) ?? 0
        }
    }

    /// day-string → review count for every recorded day within [from, to] (inclusive).
    /// Days with no row are simply absent (caller fills zeros).
    public func dailyCounts(from: Date, to: Date, calendar: Calendar = .current) throws -> [String: Int] {
        var lo = TextKey.dayString(from, calendar: calendar)
        var hi = TextKey.dayString(to, calendar: calendar)
        if lo > hi { swap(&lo, &hi) }   // day-strings are yyyy-MM-dd: lexicographic == chronological
        return try dbQueue.read { db in
            try Row.fetchAll(db, sql: "SELECT day, count FROM review_log WHERE day >= ? AND day <= ?",
                             arguments: [lo, hi])
                .reduce(into: [:]) { acc, row in acc[row["day"]] = row["count"] }
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
