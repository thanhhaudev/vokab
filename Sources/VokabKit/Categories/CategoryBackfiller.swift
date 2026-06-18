import Foundation

/// Lazily classifies Phase-1 entries that have no category yet (one agy call on
/// first detail open). Mirrors `EnrichmentService`: coalesces in-flight work per
/// id and re-reads fresh before persisting so a stale snapshot never writes.
public actor CategoryBackfiller {
    private let agy: AgyService
    private let entries: EntryRepository
    private let categories: CategoryService
    private var inFlight: [Int64: Task<String?, Error>] = [:]

    public init(agy: AgyService, entries: EntryRepository, categories: CategoryService) {
        self.agy = agy
        self.entries = entries
        self.categories = categories
    }

    /// Returns the entry's canonical category, classifying it if currently nil.
    @discardableResult
    public func backfill(entry: Entry) async throws -> String? {
        guard let id = entry.id else { return entry.category }
        guard let fresh = try entries.entry(id: id) else { return nil }
        guard fresh.category == nil else { return fresh.category }
        if let existing = inFlight[id] { return try await existing.value }

        let task = Task<String?, Error> { try await self.perform(fresh, id: id) }
        inFlight[id] = task
        do { let r = try await task.value; inFlight[id] = nil; return r }
        catch { inFlight[id] = nil; throw error }
    }

    private func perform(_ entry: Entry, id: Int64) async throws -> String? {
        let taxonomy = try categories.currentTaxonomy()
        guard let raw = try await agy.classify(entry.rawText, language: entry.language,
                                               taxonomy: taxonomy) else { return nil }
        let canonical = try categories.canonicalize(raw)
        try entries.setCategory(id: id, category: canonical)
        return canonical
    }
}
