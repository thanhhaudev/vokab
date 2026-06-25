import Foundation
import GRDB

/// agy result cache keyed by normalized text + language (SPEC §9).
public struct CacheRepository: Sendable {
    private let dbQueue: DatabaseQueue
    public init(dbQueue: DatabaseQueue) { self.dbQueue = dbQueue }

    public func lookup(text: String, language: String, meaningLanguage: String? = nil) throws -> CacheEntry? {
        let key = TextKey.cacheKey(text: text, language: language, meaningLanguage: meaningLanguage)
        return try dbQueue.read { db in try CacheEntry.fetchOne(db, key: key) }
    }

    public func upsert(text: String, language: String, meaningLanguage: String? = nil, aiResult: String, now: Date) throws {
        let key = TextKey.cacheKey(text: text, language: language, meaningLanguage: meaningLanguage)
        let entry = CacheEntry(key: key, aiResult: aiResult, createdAt: now)
        try dbQueue.write { db in try entry.save(db) }
    }

    public func lookup(text: String, language: String, minLevel: CEFR, meaningLanguage: String? = nil) throws -> CacheEntry? {
        let key = TextKey.cacheKey(text: text, language: language, minLevel: minLevel, meaningLanguage: meaningLanguage)
        return try dbQueue.read { db in try CacheEntry.fetchOne(db, key: key) }
    }

    public func upsert(text: String, language: String, minLevel: CEFR, meaningLanguage: String? = nil, aiResult: String, now: Date) throws {
        let key = TextKey.cacheKey(text: text, language: language, minLevel: minLevel, meaningLanguage: meaningLanguage)
        let entry = CacheEntry(key: key, aiResult: aiResult, createdAt: now)
        try dbQueue.write { db in try entry.save(db) }
    }

    public func clear() throws {
        _ = try dbQueue.write { db in try CacheEntry.deleteAll(db) }
    }
}
