import Foundation

/// Lazily repairs incomplete phrase entries on first detail open (mirrors
/// `RelationsBackfiller`: coalesces per id, re-reads fresh, persists via
/// setAiResult). Fills `commonErrors`/`contextOfUse`/`grammarNote` for entries
/// enriched before those existed, and the core `meaning`/`meaningEn` when the
/// model dropped them (happens for some long/slang/vulgar phrases).
public actor PhraseErrorBackfiller {
    private let agy: AgyService
    private let entries: EntryRepository
    private var inFlight: [Int64: Task<Entry?, Error>] = [:]

    public init(agy: AgyService, entries: EntryRepository) { self.agy = agy; self.entries = entries }

    @discardableResult
    public func backfill(entry: Entry) async throws -> Entry? {
        guard let id = entry.id else { return entry }
        guard let fresh = try entries.entry(id: id) else { return nil }
        guard fresh.cardType == .phrase else { return fresh }
        let card = (try? JSONCleaning.decode(PhraseCard.self, from: fresh.aiResult)) ?? Self.emptyPhrase
        let needsErrors = card.commonErrors.isEmpty || card.contextOfUse == nil || card.grammarNote == nil
        let needsMeaning = (card.meaning?.isEmpty != false) && (card.meaningEn?.isEmpty != false)
        guard needsErrors || needsMeaning else { return fresh }
        if let existing = inFlight[id] { return try await existing.value }

        let task = Task<Entry?, Error> {
            try await self.perform(fresh, id: id, card: card,
                                   needsErrors: needsErrors, needsMeaning: needsMeaning)
        }
        inFlight[id] = task
        do { let r = try await task.value; inFlight[id] = nil; return r }
        catch { inFlight[id] = nil; throw error }
    }

    private func perform(_ entry: Entry, id: Int64, card: PhraseCard,
                         needsErrors: Bool, needsMeaning: Bool) async throws -> Entry? {
        var merged = card
        // Each call returns a PARTIAL card; fold it in so existing fields survive.
        if needsErrors, let errors = try? await agy.backfillPhraseErrors(entry.rawText) {
            merged = merged.merging(errors)
        }
        if needsMeaning, let meaning = try? await agy.backfillPhraseMeaning(entry.rawText) {
            merged = merged.merging(meaning)
        }
        guard merged != card else { return entry }   // nothing fetched
        let json = String(data: try JSONEncoder().encode(merged), encoding: .utf8) ?? "{}"
        try entries.setAiResult(id: id, aiResult: json)
        return try entries.entry(id: id)
    }

    private static let emptyPhrase = try! JSONCleaning.decode(PhraseCard.self, from: "{}")
}
