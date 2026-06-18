import Foundation
import GRDB

/// Per-day agy usage counter for quota enforcement (SPEC §9).
public struct QuotaRepository: Sendable {
    private let dbQueue: DatabaseQueue
    public init(dbQueue: DatabaseQueue) { self.dbQueue = dbQueue }

    public func count(on date: Date) throws -> Int {
        let day = TextKey.dayString(date)
        return try dbQueue.read { db in
            try QuotaLog.fetchOne(db, key: day)?.callCount ?? 0
        }
    }

    /// Increments today's call count (and optional token estimate), creating the
    /// row if needed.
    public func increment(on date: Date, tokens: Int = 0) throws {
        let day = TextKey.dayString(date)
        try dbQueue.write { db in
            if var existing = try QuotaLog.fetchOne(db, key: day) {
                existing.callCount += 1
                existing.tokenEstimate += tokens
                try existing.update(db)
            } else {
                let row = QuotaLog(day: day, callCount: 1, tokenEstimate: tokens)
                try row.insert(db)
            }
        }
    }
}
