import Foundation
import GRDB

/// A captured vocabulary item. `aiResult` keeps agy's full JSON verbatim;
/// `cefr`/`language` are denormalized for fast Library filtering (SPEC §8, §16).
public struct Entry: Codable, FetchableRecord, MutablePersistableRecord, Sendable, Hashable, Identifiable {
    public var id: Int64?
    public var rawText: String
    public var type: String          // CardType.rawValue
    public var language: String
    public var sourceApp: String?
    public var sourceURL: String?
    public var capturedAt: Date
    public var aiResult: String      // JSON from agy
    public var cefr: String?         // denormalized
    public var frequency: String?    // denormalized
    public var enriched: Bool        // tier-2 fields fetched + merged
    public var analysisState: String // AnalysisState.rawValue; "ready" cho entry đã đủ
    public var category: String?     // canonical category; nil = unclassified
    public var captureSentence: String?   // original sentence the term appeared in; nil = none

    public static let databaseTableName = "entries"

    enum CodingKeys: String, CodingKey {
        case id
        case rawText = "raw_text"
        case type
        case language
        case sourceApp = "source_app"
        case sourceURL = "source_url"
        case capturedAt = "captured_at"
        case aiResult = "ai_result"
        case cefr
        case frequency
        case enriched
        case analysisState = "analysis_state"
        case category
        case captureSentence = "capture_sentence"
    }

    public mutating func didInsert(_ inserted: InsertionSuccess) {
        id = inserted.rowID
    }

    public init(id: Int64? = nil, rawText: String, type: String, language: String,
                sourceApp: String? = nil, sourceURL: String? = nil,
                capturedAt: Date, aiResult: String, cefr: String? = nil, frequency: String? = nil,
                enriched: Bool = false, analysisState: String = AnalysisState.ready.rawValue,
                category: String? = nil, captureSentence: String? = nil) {
        self.id = id
        self.rawText = rawText
        self.type = type
        self.language = language
        self.sourceApp = sourceApp
        self.sourceURL = sourceURL
        self.capturedAt = capturedAt
        self.aiResult = aiResult
        self.cefr = cefr
        self.frequency = frequency
        self.enriched = enriched
        self.analysisState = analysisState
        self.category = category
        self.captureSentence = captureSentence
    }

    public var cardType: CardType? { CardType(rawValue: type) }
}

/// SM-2 scheduling state for an entry (SPEC §8, §11).
public struct ReviewState: Codable, FetchableRecord, PersistableRecord, Sendable, Equatable {
    public var entryId: Int64
    public var easeFactor: Double
    public var interval: Int
    public var dueDate: Date
    public var reviewCount: Int
    public var lastReview: Date?
    public var cardMode: String      // CardMode.rawValue

    public static let databaseTableName = "review_state"

    enum CodingKeys: String, CodingKey {
        case entryId = "entry_id"
        case easeFactor = "ease_factor"
        case interval
        case dueDate = "due_date"
        case reviewCount = "review_count"
        case lastReview = "last_review"
        case cardMode = "card_mode"
    }

    public init(entryId: Int64, easeFactor: Double = 2.5, interval: Int = 0,
                dueDate: Date, reviewCount: Int = 0, lastReview: Date? = nil,
                cardMode: CardMode = .recognition) {
        self.entryId = entryId
        self.easeFactor = easeFactor
        self.interval = interval
        self.dueDate = dueDate
        self.reviewCount = reviewCount
        self.lastReview = lastReview
        self.cardMode = cardMode.rawValue
    }

    public var mode: CardMode { CardMode(rawValue: cardMode) ?? .recognition }
}

/// Free-form tag on an entry.
public struct Tag: Codable, FetchableRecord, PersistableRecord, Sendable, Equatable {
    public var entryId: Int64
    public var tag: String

    public static let databaseTableName = "tags"

    enum CodingKeys: String, CodingKey {
        case entryId = "entry_id"
        case tag
    }

    public init(entryId: Int64, tag: String) {
        self.entryId = entryId
        self.tag = tag
    }
}

/// Cached agy result keyed by normalized text + language (SPEC §9).
public struct CacheEntry: Codable, FetchableRecord, PersistableRecord, Sendable, Equatable {
    public var key: String
    public var aiResult: String
    public var createdAt: Date

    public static let databaseTableName = "cache"

    enum CodingKeys: String, CodingKey {
        case key
        case aiResult = "ai_result"
        case createdAt = "created_at"
    }

    public init(key: String, aiResult: String, createdAt: Date) {
        self.key = key
        self.aiResult = aiResult
        self.createdAt = createdAt
    }
}

/// Per-day count of review sessions, for the day-streak metric. `day` is "yyyy-MM-dd".
public struct ReviewLog: Codable, FetchableRecord, PersistableRecord, Sendable, Equatable {
    public var day: String
    public var count: Int

    public static let databaseTableName = "review_log"

    public init(day: String, count: Int = 0) {
        self.day = day
        self.count = count
    }
}

/// A taxonomy category. `normalizedName` (lower+trim+collapsed) is the dedup key;
/// `colorIndex` indexes a stable UI palette (SPEC §7, Phase 2).
public struct Category: Codable, FetchableRecord, MutablePersistableRecord, Sendable, Hashable {
    public var name: String              // canonical display name, e.g. "Technology"
    public var normalizedName: String
    public var colorIndex: Int
    public var isSeed: Bool
    public var createdAt: Date

    public static let databaseTableName = "categories"

    enum CodingKeys: String, CodingKey {
        case name
        case normalizedName = "normalized_name"
        case colorIndex = "color_index"
        case isSeed = "is_seed"
        case createdAt = "created_at"
    }

    public init(name: String, normalizedName: String, colorIndex: Int,
                isSeed: Bool = false, createdAt: Date) {
        self.name = name
        self.normalizedName = normalizedName
        self.colorIndex = colorIndex
        self.isSeed = isSeed
        self.createdAt = createdAt
    }
}

/// Per-day agy usage counter (SPEC §9). `day` is "yyyy-MM-dd".
public struct QuotaLog: Codable, FetchableRecord, PersistableRecord, Sendable, Equatable {
    public var day: String
    public var callCount: Int
    public var tokenEstimate: Int

    public static let databaseTableName = "quota_log"

    enum CodingKeys: String, CodingKey {
        case day
        case callCount = "call_count"
        case tokenEstimate = "token_estimate"
    }

    public init(day: String, callCount: Int = 0, tokenEstimate: Int = 0) {
        self.day = day
        self.callCount = callCount
        self.tokenEstimate = tokenEstimate
    }
}
