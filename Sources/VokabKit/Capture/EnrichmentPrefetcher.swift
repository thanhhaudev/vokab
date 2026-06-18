import Foundation

/// Runs tier-2 enrichment in the background after capture, so a detail view is
/// usually already enriched by the time it opens. Concurrency is bounded by an
/// `AsyncSemaphore` to avoid an agy-process burst on rapid captures. De-duping
/// and CAS safety come for free from `EnrichmentService`: it coalesces in-flight
/// work per id and re-reads fresh before persisting.
public actor EnrichmentPrefetcher {
    private let enrichment: EnrichmentService
    private let entries: EntryRepository
    private let gate: AsyncSemaphore
    private let onChange: @Sendable () -> Void

    /// - Parameters:
    ///   - maxConcurrent: max simultaneous background enrichments (default 1 —
    ///     background work, no rush; foreground captures keep priority).
    ///   - onChange: called after each entry is successfully enriched, so the UI
    ///     can refresh. Must be safe to call from a background context.
    public init(enrichment: EnrichmentService, entries: EntryRepository,
                maxConcurrent: Int = 1, onChange: @escaping @Sendable () -> Void) {
        self.enrichment = enrichment
        self.entries = entries
        self.gate = AsyncSemaphore(max(1, maxConcurrent))
        self.onChange = onChange
    }

    /// Schedules a background enrichment for one entry id. Returns immediately.
    public func prefetch(id: Int64) {
        Task { await self.run(id: id) }
    }

    /// Schedules background enrichment for several ids (e.g. chosen paragraph words).
    public func prefetch(ids: [Int64]) {
        for id in ids { prefetch(id: id) }
    }

    private func run(id: Int64) async {
        await gate.wait()
        let entry = try? entries.entry(id: id)
        if let entry {
            if (try? await enrichment.enrich(entry: entry)) != nil { onChange() }
        }
        await gate.signal()
    }
}
