import Foundation

/// Coalesces background WORD enrichment: ids submitted close together share ONE
/// batched extras call + ONE batched relations call (each `agy` call has ~8s
/// fixed overhead, so batching is a large win on rapid captures).
///
/// Coalescing is purely an optimization and MUST NOT drop or corrupt enrichment.
/// Anything the batch can't cover — words still needing a core fetch, words the
/// batch response omitted, or a failed batch call — falls back to the per-item
/// `EnrichmentService.enrich(entry:)` path, which is the authoritative engine
/// (core fetch, merge, CAS markEnriched, in-flight coalescing). The batch path
/// faithfully mirrors that service's word merge + markEnriched.
public actor BatchEnricher {
    private let agy: AgyService
    private let entries: EntryRepository
    private let fallback: EnrichmentService
    private let language: String
    private let onChange: (@Sendable () -> Void)?
    private var coalescer: JobCoalescer<Int64>!

    /// - Parameter onChange: called after each entry is enriched (batch or
    ///   fallback) so the UI can refresh. Safe to call from a background context.
    public init(agy: AgyService, entries: EntryRepository, fallback: EnrichmentService,
                maxBatch: Int = 8, window: TimeInterval = 2.0,
                onChange: (@Sendable () -> Void)? = nil) {
        self.agy = agy
        self.entries = entries
        self.fallback = fallback
        self.language = "en"
        self.onChange = onChange
        self.coalescer = JobCoalescer(maxBatch: maxBatch, window: window) { [weak self] ids in
            await self?.flush(ids)
        }
    }

    /// Schedules background enrichment for one WORD entry id. Coalesces with other
    /// ids submitted within the window.
    public func submit(id: Int64) async { await coalescer.submit(id) }

    /// Flushes any pending batch and waits for it to finish (tests / shutdown).
    public func waitQuiescent() async { await coalescer.waitQuiescent() }

    private func flush(_ ids: [Int64]) async {
        // 1. Load fresh; keep words that exist and are not yet enriched.
        var candidates: [Entry] = []
        for id in ids {
            guard let entry = (try? entries.entry(id: id)) ?? nil else { continue }
            guard entry.cardType == .word, entry.enriched == false else { continue }
            candidates.append(entry)
        }
        guard !candidates.isEmpty else { return }

        // 2. Words still needing CORE (paragraph-origin, no ipa/meaning) go to the
        //    per-item fallback, which fetches core correctly. Never batch them.
        var batchable: [Entry] = []
        for entry in candidates {
            let card = (try? JSONCleaning.decode(WordCard.self, from: entry.aiResult)) ?? Self.emptyWord
            if card.ipa == nil && card.meaningEn == nil {
                await fallbackEnrich(entry)
            } else {
                batchable.append(entry)
            }
        }
        guard !batchable.isEmpty else { return }

        // 3. Group by language so each batched prompt names the right language
        //    (usually one group, "en").
        let byLanguage = Dictionary(grouping: batchable, by: { $0.language })
        for (lang, group) in byLanguage {
            await flushGroup(group, language: lang)
        }
    }

    private func flushGroup(_ group: [Entry], language lang: String) async {
        let words = group.map { $0.rawText }
        async let extrasTask = try? agy.enrichWordExtrasBatch(words, language: lang)
        async let relationsTask = try? agy.enrichWordRelationsBatch(words, language: lang)
        let (extras, relations) = await (extrasTask, relationsTask)

        for entry in group {
            let key = entry.rawText
            let a = extras?[key] ?? extras?[key.lowercased()]
            let b = relations?[key] ?? relations?[key.lowercased()]
            if a == nil && b == nil {
                // Batch omitted this word (or both calls failed) → per-item fallback.
                await fallbackEnrich(entry)
                continue
            }
            // Merge the partial halves into the stored card — mirrors
            // EnrichmentService.performEnrich for `.word`.
            guard let id = entry.id else { continue }
            var card = (try? JSONCleaning.decode(WordCard.self, from: entry.aiResult)) ?? Self.emptyWord
            if let a { card = card.merging(a) }
            if let b { card = card.merging(b) }
            if let json = try? encode(card) {
                try? entries.markEnriched(id: id, aiResult: json)
                onChange?()
            }
        }
    }

    /// Per-item fallback; never throws out of `flush` so one entry's failure can't
    /// abort the rest of the batch.
    private func fallbackEnrich(_ entry: Entry) async {
        if (try? await fallback.enrich(entry: entry)) != nil { onChange?() }
    }

    private func encode<T: Encodable>(_ value: T) throws -> String {
        String(data: try JSONEncoder().encode(value), encoding: .utf8) ?? "{}"
    }

    private static let emptyWord = try! JSONCleaning.decode(WordCard.self, from: "{}")
}
