import Foundation

/// Fetches tier-2 (enrichment) fields for a captured entry, merges them into the
/// stored core card, persists, and marks the entry enriched.
///
/// An `actor` so it can coalesce in-flight work: concurrent `enrich(entry:)` calls
/// for the same entry id await the *same* task instead of each spending agy calls.
public actor EnrichmentService {
    private let agy: AgyService
    private let entries: EntryRepository
    private var inFlight: [Int64: Task<Entry, Error>] = [:]

    public init(agy: AgyService, entries: EntryRepository) {
        self.agy = agy
        self.entries = entries
    }

    @discardableResult
    public func enrich(entry: Entry) async throws -> Entry {
        guard let id = entry.id else { return entry }
        // Re-read fresh rather than trusting the caller's snapshot. A genuine DB
        // error propagates (caller's error path handles it); a missing row means
        // the entry was deleted → nothing to enrich. Never fabricate enrichment
        // from a stale snapshot.
        guard let fresh = try entries.entry(id: id) else { return entry }
        guard fresh.enriched == false else { return fresh }
        // Coalesce: a concurrent caller for the same id awaits the same task.
        if let existing = inFlight[id] { return try await existing.value }

        let task = Task<Entry, Error> { try await self.performEnrich(fresh, id: id) }
        inFlight[id] = task
        do { let result = try await task.value; inFlight[id] = nil; return result }
        catch { inFlight[id] = nil; throw error }
    }

    private func performEnrich(_ entry: Entry, id: Int64) async throws -> Entry {
        let json: String
        switch entry.cardType {
        case .word:
            var card = (try? JSONCleaning.decode(WordCard.self, from: entry.aiResult)) ?? Self.emptyWord
            // Paragraph-origin words lack core fields (ipa/meaning_en/examples) →
            // fetch the core first so they reach parity with a typed word.
            var coreFetched = false
            if card.ipa == nil && card.meaningEn == nil {
                if let core = try? await agy.defineWordCore(entry.rawText, language: entry.language, taxonomy: []) {
                    card = card.merging(core)   // partial (meaning/cefr/pos) wins; core fills the rest
                    coreFetched = true
                }
            }
            // Two enrichment halves in parallel; each tolerated independently.
            async let extras = try? agy.enrichWordExtras(entry.rawText, language: entry.language)
            async let relations = try? agy.enrichWordRelations(entry.rawText, language: entry.language)
            let (a, b) = await (extras, relations)
            guard coreFetched || a != nil || b != nil else { return entry }   // all failed → retry later
            if let a { card = card.merging(a) }
            if let b { card = card.merging(b) }
            json = try encode(card)
            try entries.markEnriched(id: id, aiResult: json)
            try? entries.seedAliases(entryId: id, forms: card.forms, language: entry.language)
            return try entries.entry(id: id) ?? entry
        case .phrase:
            var card = (try? JSONCleaning.decode(PhraseCard.self, from: entry.aiResult)) ?? Self.emptyPhrase
            async let extras = try? agy.enrichPhraseExtras(entry.rawText)
            async let relations = try? agy.enrichPhraseRelations(entry.rawText)
            let (a, b) = await (extras, relations)
            guard a != nil || b != nil else { return entry }
            if let a { card = card.merging(a) }
            if let b { card = card.merging(b) }
            json = try encode(card)
        default:
            return entry   // paragraph items are not enriched
        }

        try entries.markEnriched(id: id, aiResult: json)
        return try entries.entry(id: id) ?? entry
    }

    private func encode<T: Encodable>(_ value: T) throws -> String {
        String(data: try JSONEncoder().encode(value), encoding: .utf8) ?? "{}"
    }

    private static let emptyWord = try! JSONCleaning.decode(WordCard.self, from: "{}")
    private static let emptyPhrase = try! JSONCleaning.decode(PhraseCard.self, from: "{}")
}
