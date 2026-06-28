import Foundation

/// Lazily fills `collocations`/`confusables` on word entries that were enriched
/// before those fields existed (one agy call on first detail open). Mirrors
/// `CategoryBackfiller`/`EnrichmentService`: coalesces in-flight work per id and
/// re-reads fresh before persisting so a stale snapshot never writes.
public actor RelationsBackfiller {
    private let agy: AgyService
    private let entries: EntryRepository
    private var inFlight: [Int64: Task<Entry?, Error>] = [:]

    public init(agy: AgyService, entries: EntryRepository) {
        self.agy = agy
        self.entries = entries
    }

    /// Returns the entry with relations filled in, the entry unchanged when it is
    /// not a word / already has the fields, or nil when the row is gone.
    @discardableResult
    public func backfill(entry: Entry) async throws -> Entry? {
        guard let id = entry.id else { return entry }
        guard let fresh = try entries.entry(id: id) else { return nil }
        guard fresh.cardType == .word else { return fresh }
        let card = (try? JSONCleaning.decode(WordCard.self, from: fresh.aiResult)) ?? Self.emptyWord
        let needsBackfill = (card.collocations.isEmpty && card.confusables.isEmpty)
            || card.contextOfUse == nil || card.grammarNote == nil
            || card.irregular == nil          // forms never fetched
            // forms present but bare ({label,form} only, no gloss/ipa/examples) →
            // a card enriched before the per-form fields existed; re-fetch.
            || (!card.forms.isEmpty && !WordCard.formsHaveDetail(card.forms))
        guard needsBackfill else { return fresh }
        if let existing = inFlight[id] { return try await existing.value }

        let task = Task<Entry?, Error> { try await self.perform(fresh, id: id, card: card) }
        inFlight[id] = task
        do { let r = try await task.value; inFlight[id] = nil; return r }
        catch { inFlight[id] = nil; throw error }
    }

    private func perform(_ entry: Entry, id: Int64, card: WordCard) async throws -> Entry? {
        guard let relations = try? await agy.backfillWordRelations(entry.rawText, language: entry.language) else {
            return entry   // agy failed → leave as-is, try again next open
        }
        let merged = card.merging(relations)
        let json = String(data: try JSONEncoder().encode(merged), encoding: .utf8) ?? "{}"
        try entries.setAiResult(id: id, aiResult: json)
        try? entries.seedAliases(entryId: id, forms: merged.forms, language: entry.language)
        return try entries.entry(id: id)
    }

    private static let emptyWord = try! JSONCleaning.decode(WordCard.self, from: "{}")
}
