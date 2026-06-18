import Foundation

/// Lazily fills `commonErrors` on phrase entries enriched before the structured
/// error-quiz shape existed (one agy call on first detail open). Mirrors
/// `RelationsBackfiller`: coalesces per id, re-reads fresh, persists via setAiResult.
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
        guard card.commonErrors.isEmpty else { return fresh }
        if let existing = inFlight[id] { return try await existing.value }

        let task = Task<Entry?, Error> { try await self.perform(fresh, id: id, card: card) }
        inFlight[id] = task
        do { let r = try await task.value; inFlight[id] = nil; return r }
        catch { inFlight[id] = nil; throw error }
    }

    private func perform(_ entry: Entry, id: Int64, card: PhraseCard) async throws -> Entry? {
        guard let errors = try? await agy.backfillPhraseErrors(entry.rawText) else { return entry }
        let merged = card.merging(errors)
        let json = String(data: try JSONEncoder().encode(merged), encoding: .utf8) ?? "{}"
        try entries.setAiResult(id: id, aiResult: json)
        return try entries.entry(id: id)
    }

    private static let emptyPhrase = try! JSONCleaning.decode(PhraseCard.self, from: "{}")
}
