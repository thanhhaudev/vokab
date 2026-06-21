import Foundation

/// Outcome of the synchronous `beginCapture` phase.
public enum BeganCapture: Sendable, Equatable {
    case duplicate(entryId: Int64, type: CardType)
    case ready(entryId: Int64, type: CardType)
    case pending(entryId: Int64, type: CardType)
    case paragraph
    case blocked(behavior: QuotaHitBehavior)
}

/// Outcome of a capture.
public struct CaptureResult: Sendable, Equatable {
    public let type: CardType
    /// Set for word/phrase captures (the inserted or existing entry).
    public let entryId: Int64?
    /// Set for paragraph captures: candidate items for the extraction UI.
    public let paragraphItems: [ParagraphItem]
    public let wasDuplicate: Bool
    public let fromCache: Bool
    /// Set for paragraph captures: full learner-language translation of the passage.
    public let translationVi: String?
    /// Set for paragraph captures: count of chunks that failed (0 = none / not chunked).
    public let failedChunks: Int
}

/// Result of a paragraph extraction fetch at one CEFR level (the screen merges
/// these as the user lowers the Min-level filter). `failedChunks` > 0 means some
/// chunks of a long passage failed but the rest succeeded (SPEC §7c).
public struct ParagraphFetch: Sendable, Equatable {
    public let items: [ParagraphItem]
    public let translationVi: String?
    public let failedChunks: Int
    public init(items: [ParagraphItem], translationVi: String?, failedChunks: Int) {
        self.items = items; self.translationVi = translationVi; self.failedChunks = failedChunks
    }
}

public enum CaptureError: Error, Equatable, Sendable {
    /// Daily agy quota reached; `behavior` is the user's configured response.
    case quotaExceeded(behavior: QuotaHitBehavior)
}

/// Orchestrates a capture: classify → dedup → cache → quota → agy → persist
/// (SPEC §6, §9). agy/transport failures propagate so that no entry is written
/// and no quota is charged (SPEC §10).
public struct CaptureService: Sendable {
    /// Paragraphs longer than this (in words) are split into sentence-aligned
    /// chunks so agy doesn't summarize a wall of text (SPEC §7c).
    static let paragraphChunkMaxWords = 120
    private let agy: AgyService
    private let entries: EntryRepository
    private let cache: CacheRepository
    private let quota: QuotaRepository
    private let categories: CategoryService
    private let settings: VokabSettings

    public init(agy: AgyService, entries: EntryRepository, cache: CacheRepository,
                quota: QuotaRepository, categories: CategoryService, settings: VokabSettings) {
        self.agy = agy
        self.entries = entries
        self.cache = cache
        self.quota = quota
        self.categories = categories
        self.settings = settings
    }

    public func capture(text: String, language: String, source: SourceContext,
                        forcedType: CardType? = nil,
                        minLevelOverride: CEFR? = nil) async throws -> CaptureResult {
        let type = forcedType ?? InputClassifier.classify(text)
        let now = source.capturedAt

        switch type {
        case .word, .phrase:
            return try await captureSingle(type: type, text: text, language: language, source: source, now: now)
        case .paragraphItem:
            return try await captureParagraph(text: text, language: language,
                                              minLevel: minLevelOverride ?? settings.minParagraphLevel, now: now)
        }
    }

    /// Pha ĐỒNG BỘ (tức thì): classify → dedup → cache → quota; word/phrase miss →
    /// chèn entry "analyzing" và trả `.pending`. KHÔNG gọi agy.
    public func beginCapture(text: String, language: String, source: SourceContext,
                             forcedType: CardType? = nil) throws -> BeganCapture {
        let type = forcedType ?? InputClassifier.classify(text)
        let now = source.capturedAt
        guard type == .word || type == .phrase else { return .paragraph }

        if let existing = try entries.find(rawText: text, language: language) {
            return .duplicate(entryId: existing.id ?? -1, type: existing.cardType ?? type)
        }
        if let cached = try cache.lookup(text: text, language: language) {
            let meta = singleMeta(type: type, json: cached.aiResult)
            let category = try categories.canonicalize(meta.category, now: now)
            let id = try persistEntry(type: type, text: text, language: language,
                                      json: cached.aiResult, cefr: meta.cefr, frequency: meta.frequency,
                                      category: category, source: source, now: now)
            return .ready(entryId: id, type: type)
        }
        let status = quotaStatus(on: now)
        if status.shouldBlock { return .blocked(behavior: settings.quotaHitBehavior) }

        let entry = Entry(rawText: text, type: type.rawValue, language: language,
                          sourceApp: source.appName, sourceURL: source.url,
                          capturedAt: now, aiResult: "{}",
                          analysisState: AnalysisState.analyzing.rawValue)
        let id = try entries.insertCapture(entry, dueDate: now, startingEase: settings.startingEase)
        return .pending(entryId: id, type: type)
    }

    public enum AnalysisOutcome: Sendable { case ready, failed, skipped }

    /// Background tier-1 analysis. Returns the outcome so callers can react
    /// (e.g. notify on failure). Never throws — transport errors mark the entry failed.
    @discardableResult
    public func runAnalysis(entryId: Int64) async -> AnalysisOutcome {
        guard let entry = try? entries.entry(id: entryId),
              entry.analysisState == AnalysisState.analyzing.rawValue,
              let type = entry.cardType else { return .skipped }
        let language = entry.language
        let text = entry.rawText
        let taxonomy = (try? categories.currentTaxonomy()) ?? []
        do {
            let json: String; let cefr: String?; let frequency: String?; let rawCategory: String?
            if type == .word {
                let card = try await agy.defineWordCore(text, language: language, taxonomy: taxonomy)
                json = try encode(card); cefr = card.cefrLevel; frequency = card.frequency; rawCategory = card.category
            } else {
                let card = try await agy.analyzePhraseCore(text, taxonomy: taxonomy)
                json = try encode(card); cefr = card.cefrLevel; frequency = nil; rawCategory = card.category
            }
            try quota.increment(on: entry.capturedAt)
            try cache.upsert(text: text, language: language, aiResult: json, now: entry.capturedAt)
            let category = try categories.canonicalize(rawCategory, now: entry.capturedAt)
            _ = try entries.markAnalyzed(id: entryId, aiResult: json, cefr: cefr, frequency: frequency, category: category)
            return .ready
        } catch {
            try? entries.markAnalysisFailed(id: entryId)
            return .failed
        }
    }

    /// Persists a chosen paragraph item as a first-class **word** entry (seeded
    /// with the item's partial fields) so it gets the same detail + enrichment as
    /// a typed word. Background prep fills the rest (see EnrichmentService).
    /// Returns the new entry id.
    @discardableResult
    public func persistParagraphItem(_ item: ParagraphItem, language: String,
                                     source: SourceContext, sourceText: String? = nil) throws -> Int64 {
        let word = item.word ?? ""
        let sentence = sourceText.flatMap {
            SentenceExtractor.extractSentence(containing: word, from: $0)
        }
        // Dedupe guard (SPEC §11): if this word already exists, don't insert a
        // duplicate — backfill any missing capture context and return its id.
        if let existing = try entries.find(rawText: word, language: language), let id = existing.id {
            try entries.backfillCaptureContextIfMissing(
                id: id, captureSentence: sentence,
                sourceApp: source.appName, sourceURL: source.url)
            return id
        }
        // Build a partial WordCard JSON (snake_case keys, decoded leniently later).
        var fields: [String: String] = [:]
        if let p = item.pos { fields["pos"] = p }
        if let m = item.meaningVi { fields["meaning_vi"] = m }
        if let c = item.cefr { fields["cefr_level"] = c }
        if let cat = item.category { fields["category"] = cat }
        let json = (try? encode(fields)) ?? "{}"
        let category = try categories.canonicalize(item.category)
        let entry = Entry(rawText: word,
                          type: CardType.word.rawValue,
                          language: language,
                          sourceApp: source.appName,
                          sourceURL: source.url,
                          capturedAt: source.capturedAt,
                          aiResult: json,
                          cefr: item.cefr?.lowercased(),
                          category: category,
                          captureSentence: sentence)
        return try entries.insertCapture(entry, dueDate: source.capturedAt, startingEase: settings.startingEase)
    }

    // MARK: - Word / phrase

    private func captureSingle(type: CardType, text: String, language: String,
                               source: SourceContext, now: Date) async throws -> CaptureResult {
        if let existing = try entries.find(rawText: text, language: language) {
            return CaptureResult(type: existing.cardType ?? type, entryId: existing.id,
                                 paragraphItems: [], wasDuplicate: true, fromCache: false,
                                 translationVi: nil, failedChunks: 0)
        }

        if let cached = try cache.lookup(text: text, language: language) {
            let meta = singleMeta(type: type, json: cached.aiResult)
            let category = try categories.canonicalize(meta.category, now: now)
            let id = try persistEntry(type: type, text: text, language: language,
                                      json: cached.aiResult, cefr: meta.cefr, frequency: meta.frequency,
                                      category: category, source: source, now: now)
            return CaptureResult(type: type, entryId: id, paragraphItems: [],
                                 wasDuplicate: false, fromCache: true,
                                 translationVi: nil, failedChunks: 0)
        }

        try checkQuota(now)
        let taxonomy = (try? categories.currentTaxonomy()) ?? []

        let json: String
        let cefr: String?
        let frequency: String?
        let rawCategory: String?
        if type == .word {
            let card = try await agy.defineWordCore(text, language: language, taxonomy: taxonomy)
            json = try encode(card); cefr = card.cefrLevel; frequency = card.frequency; rawCategory = card.category
        } else {
            let card = try await agy.analyzePhraseCore(text, taxonomy: taxonomy)
            json = try encode(card); cefr = card.cefrLevel; frequency = nil; rawCategory = card.category
        }

        // Success: charge quota, cache, persist.
        try quota.increment(on: now)
        try cache.upsert(text: text, language: language, aiResult: json, now: now)
        let category = try categories.canonicalize(rawCategory, now: now)
        let id = try persistEntry(type: type, text: text, language: language,
                                  json: json, cefr: cefr, frequency: frequency,
                                  category: category, source: source, now: now)
        return CaptureResult(type: type, entryId: id, paragraphItems: [],
                             wasDuplicate: false, fromCache: false,
                             translationVi: nil, failedChunks: 0)
    }

    // MARK: - Paragraph

    private func captureParagraph(text: String, language: String, minLevel: CEFR, now: Date) async throws -> CaptureResult {
        let fetch = try await fetchParagraph(text: text, language: language, minLevel: minLevel, now: now)
        return CaptureResult(type: .paragraphItem, entryId: nil, paragraphItems: fetch.items,
                             wasDuplicate: false, fromCache: false,
                             translationVi: fetch.translationVi, failedChunks: fetch.failedChunks)
    }

    /// Re-runs paragraph extraction at a chosen minimum CEFR level. Caches per
    /// (text, language, level); charges quota only on a real agy call. Persists
    /// nothing — words are saved only via `persistParagraphItem`.
    public func reextractParagraph(text: String, language: String, minLevel: CEFR,
                                   now: Date = Date()) async throws -> ParagraphFetch {
        try await fetchParagraph(text: text, language: language, minLevel: minLevel, now: now)
    }

    /// Shared cache→agy paragraph fetch. Long text is split into sentence-aligned
    /// chunks; quota is charged once per successful chunk (SPEC §7c, §10).
    private func fetchParagraph(text: String, language: String, minLevel: CEFR,
                               now: Date) async throws -> ParagraphFetch {
        if let cached = try cache.lookup(text: text, language: language, minLevel: minLevel),
           let ex = try? JSONCleaning.decode(ParagraphExtraction.self, from: cached.aiResult) {
            return ParagraphFetch(items: ex.items, translationVi: ex.translationVi, failedChunks: 0)
        }
        try checkQuota(now)
        let taxonomy = (try? categories.currentTaxonomy()) ?? []
        let chunks = ParagraphChunker.chunk(text, maxWords: Self.paragraphChunkMaxWords)

        var merged: [ParagraphItem] = []
        var translations: [String] = []
        var failed = 0
        for chunk in chunks {
            do {
                let ex = try await agy.extractFromParagraph(chunk, minLevel: minLevel, taxonomy: taxonomy)
                try quota.increment(on: now)                 // charge only on success (SPEC §10)
                merged = ParagraphMerge.union(merged, ex.items)
                if let t = ex.translationVi?.trimmingCharacters(in: .whitespacesAndNewlines), !t.isEmpty {
                    translations.append(t)
                }
            } catch {
                failed += 1                                  // not charged; partial failure
            }
        }
        // Every chunk failed → surface as a hard failure (no entry, no cache).
        if failed == chunks.count && !chunks.isEmpty {
            throw AgyError.timeout
        }
        let extraction = ParagraphExtraction(
            translationVi: translations.isEmpty ? nil : translations.joined(separator: " "),
            items: merged)
        let json = (try? encode(extraction)) ?? #"{"items":[]}"#
        try cache.upsert(text: text, language: language, minLevel: minLevel, aiResult: json, now: now)
        return ParagraphFetch(items: merged, translationVi: extraction.translationVi, failedChunks: failed)
    }

    // MARK: - Quota

    public struct QuotaStatus: Sendable, Equatable {
        public let used: Int
        public let limit: Int
        public let overWarn: Bool      // used >= limit (ngưỡng cảnh báo)
        public let shouldBlock: Bool   // overWarn && hardBlockOnLimit
    }

    /// Trạng thái quota local hiện tại (không throw). UI dùng để cảnh báo.
    public func quotaStatus(on now: Date) -> QuotaStatus {
        let count = try? quota.count(on: now)
        let used = count ?? 0
        let over = used >= settings.dailyLimit
        // Fail-closed: if the count is unreadable and hard-block is on, treat as blocking.
        let shouldBlock = settings.hardBlockOnLimit && (over || count == nil)
        return QuotaStatus(used: used, limit: settings.dailyLimit,
                           overWarn: over, shouldBlock: shouldBlock)
    }

    public func pendingEntryIdsForResume() throws -> [Int64] { try entries.pendingEntryIds() }

    private func checkQuota(_ now: Date) throws {
        let status = quotaStatus(on: now)
        if status.shouldBlock {
            throw CaptureError.quotaExceeded(behavior: settings.quotaHitBehavior)
        }
    }

    // MARK: - Helpers

    private func persistEntry(type: CardType, text: String, language: String, json: String,
                              cefr: String?, frequency: String?, category: String?,
                              source: SourceContext, now: Date) throws -> Int64 {
        let entry = Entry(rawText: text, type: type.rawValue, language: language,
                          sourceApp: source.appName, sourceURL: source.url,
                          capturedAt: now, aiResult: json,
                          cefr: cefr?.lowercased(), frequency: frequency, category: category)
        return try entries.insertCapture(entry, dueDate: now, startingEase: settings.startingEase)
    }

    private func singleMeta(type: CardType, json: String) -> (cefr: String?, frequency: String?, category: String?) {
        if type == .word, let card = try? JSONCleaning.decode(WordCard.self, from: json) {
            return (card.cefrLevel, card.frequency, card.category)
        }
        if type == .phrase, let card = try? JSONCleaning.decode(PhraseCard.self, from: json) {
            return (card.cefrLevel, nil, card.category)
        }
        return (nil, nil, nil)
    }

    private func encode<T: Encodable>(_ value: T) throws -> String {
        let encoder = JSONEncoder()
        let data = try encoder.encode(value)
        return String(data: data, encoding: .utf8) ?? "{}"
    }
}
