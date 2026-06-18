import Foundation

/// Translates a sentence into the user's meaning language via agy, cached by
/// sentence so each sentence costs at most one agy call ever.
public actor TranslationService {
    private let agy: AgyService
    private let cache: CacheRepository
    private var inFlight: [String: Task<String?, Error>] = [:]

    public init(agy: AgyService, cache: CacheRepository) { self.agy = agy; self.cache = cache }

    /// Translates `sentence` into `langCode` ("vi"). Returns nil for empty input
    /// or English target (source is already English). Uses the cache table.
    public func translate(_ sentence: String, to langCode: String, now: Date = Date()) async throws -> String? {
        let s = sentence.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !s.isEmpty, langCode != "en" else { return nil }
        let cacheLang = "tr_" + langCode
        if let hit = try? cache.lookup(text: s, language: cacheLang) { return hit.aiResult }
        let key = cacheLang + "|" + s
        if let existing = inFlight[key] { return try await existing.value }
        let task = Task<String?, Error> {
            guard let t = try await self.agy.translate(s, to: Self.languageName(langCode)) else { return nil }
            try? self.cache.upsert(text: s, language: cacheLang, aiResult: t, now: now)
            return t
        }
        inFlight[key] = task
        do { let r = try await task.value; inFlight[key] = nil; return r }
        catch { inFlight[key] = nil; throw error }
    }

    static func languageName(_ code: String) -> String { code == "vi" ? "Vietnamese" : "English" }
}
