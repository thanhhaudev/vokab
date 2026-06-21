import Foundation

/// High-level, typed access to agy: builds prompts, runs them through an
/// `AgyRunner`, cleans + decodes the JSON, and applies the configured
/// decode-failure retry behavior (SPEC §7, §10).
public struct AgyService: Sendable {
    private let runner: AgyRunner
    private let settings: VokabSettings
    /// Optional in-flight tracker; brackets every call so the UI can show a
    /// "AI is working" indicator for all background agy work.
    private let activity: AgyActivity?

    public init(runner: AgyRunner, settings: VokabSettings, activity: AgyActivity? = nil) {
        self.runner = runner
        self.settings = settings
        self.activity = activity
    }

    public func defineWord(_ word: String, language: String) async throws -> WordCard {
        try await callAndDecode(WordCard.self, prompt: PromptTemplates.word(word, language: language))
    }

    public func analyzePhrase(_ phrase: String) async throws -> PhraseCard {
        try await callAndDecode(PhraseCard.self, prompt: PromptTemplates.phrase(phrase))
    }

    // MARK: Two-tier (core capture + lazy enrichment)

    public func defineWordCore(_ word: String, language: String, taxonomy: [String]) async throws -> WordCard {
        try await callAndDecode(WordCard.self,
            prompt: PromptTemplates.wordCore(word, language: language, taxonomy: taxonomy))
    }
    public func analyzePhraseCore(_ phrase: String, taxonomy: [String]) async throws -> PhraseCard {
        try await callAndDecode(PhraseCard.self,
            prompt: PromptTemplates.phraseCore(phrase, taxonomy: taxonomy))
    }

    /// Classify-only call for lazy backfill. Returns nil if agy omits a category.
    public func classify(_ text: String, language: String, taxonomy: [String]) async throws -> String? {
        struct Result: Decodable { let category: String? }
        let r = try await callAndDecode(Result.self,
            prompt: PromptTemplates.classify(text, language: language, taxonomy: taxonomy))
        let trimmed = r.category?.trimmingCharacters(in: .whitespacesAndNewlines)
        return (trimmed?.isEmpty == false) ? trimmed : nil
    }

    // Enrichment runs on the (faster) enrich model, split into two parallel halves.
    public func enrichWordExtras(_ word: String, language: String) async throws -> WordCard {
        try await callAndDecode(WordCard.self, prompt: PromptTemplates.wordEnrichExtras(word, language: language),
                                model: settings.enrichModel)
    }
    public func enrichWordRelations(_ word: String, language: String) async throws -> WordCard {
        try await callAndDecode(WordCard.self, prompt: PromptTemplates.wordEnrichRelations(word, language: language),
                                model: settings.enrichModel)
    }
    /// Returns a PARTIAL WordCard with only `collocations`/`confusables` populated.
    /// Callers MUST fold it into the stored card via `WordCard.merging(_:)`, never
    /// overwrite — otherwise every other field (ipa, meaning, synonyms…) is lost.
    public func backfillWordRelations(_ word: String, language: String) async throws -> WordCard {
        try await callAndDecode(WordCard.self, prompt: PromptTemplates.wordRelationsBackfill(word, language: language),
                                model: settings.enrichModel)
    }
    /// Enrich several words' "extras" in one agy call. Returns a dict keyed by the
    /// input word (case-insensitive). Words missing from the response are absent.
    public func enrichWordExtrasBatch(_ words: [String], language: String) async throws -> [String: WordCard] {
        try await callAndDecodeBatch(words: words,
            prompt: PromptTemplates.wordExtrasBatch(words: words, language: language))
    }

    /// Same, for "relations".
    public func enrichWordRelationsBatch(_ words: [String], language: String) async throws -> [String: WordCard] {
        try await callAndDecodeBatch(words: words,
            prompt: PromptTemplates.wordRelationsBatch(words: words, language: language))
    }

    public func enrichPhraseExtras(_ phrase: String) async throws -> PhraseCard {
        try await callAndDecode(PhraseCard.self, prompt: PromptTemplates.phraseEnrichExtras(phrase),
                                model: settings.enrichModel)
    }
    public func enrichPhraseRelations(_ phrase: String) async throws -> PhraseCard {
        try await callAndDecode(PhraseCard.self, prompt: PromptTemplates.phraseEnrichRelations(phrase),
                                model: settings.enrichModel)
    }
    /// Returns a PARTIAL PhraseCard with only `commonErrors` populated. Callers
    /// MUST fold it into the stored card via `merging`, never overwrite.
    public func backfillPhraseErrors(_ phrase: String) async throws -> PhraseCard {
        try await callAndDecode(PhraseCard.self, prompt: PromptTemplates.phraseErrorsBackfill(phrase),
                                model: settings.enrichModel)
    }

    public func extractFromParagraph(_ paragraph: String, taxonomy: [String]) async throws -> ParagraphExtraction {
        try await extractFromParagraph(paragraph, minLevel: settings.minParagraphLevel, taxonomy: taxonomy)
    }

    public func extractFromParagraph(_ paragraph: String, minLevel: CEFR, taxonomy: [String]) async throws -> ParagraphExtraction {
        try await callAndDecode(ParagraphExtraction.self,
                                prompt: PromptTemplates.paragraph(paragraph, minLevel: minLevel, taxonomy: taxonomy))
    }

    public func translate(_ text: String, to language: String) async throws -> String? {
        struct R: Decodable { let translation: String? }
        let r = try await callAndDecode(R.self, prompt: PromptTemplates.translate(text, language: language),
                                        model: settings.enrichModel)
        let t = r.translation?.trimmingCharacters(in: .whitespacesAndNewlines)
        return (t?.isEmpty == false) ? t : nil
    }

    public func judgeProduction(word: String, sentence: String) async throws -> ProductionFeedback {
        try await callAndDecode(ProductionFeedback.self,
                                prompt: PromptTemplates.production(word: word, sentence: sentence))
    }

    // MARK: - Core

    /// One element of a batched-enrichment array: the echoed `word` key plus the
    /// whole object decoded as a `WordCard` (so per-item field shape is identical
    /// to the single-word path). Reuses `GenericKey`, the same dynamic coding key
    /// the card decoders use.
    private struct KeyedWordCard: Decodable {
        let word: String
        let card: WordCard
        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: GenericKey.self)
            // `.convertFromSnakeCase` leaves single-token "word" unchanged.
            self.word = (try? c.decode(String.self, forKey: GenericKey(stringValue: "word")!)) ?? ""
            self.card = try WordCard(from: decoder)
        }
    }

    /// Runs a batched enrichment prompt (one agy call → JSON array) and maps it
    /// to `[inputWord: WordCard]`. Returned cards are keyed by the matching INPUT
    /// spelling (case-insensitive) so callers look up by what they passed; if no
    /// input matches a returned `word`, it is keyed by that word lowercased.
    /// Empty `word` keys are skipped. Decode failure throws `AgyError.decodeFailure`
    /// (same path as the single-word methods) so callers' fallback triggers.
    private func callAndDecodeBatch(words: [String], prompt: String) async throws -> [String: WordCard] {
        let entries = try await callAndDecode([KeyedWordCard].self, prompt: prompt, model: settings.enrichModel)
        // Map lowercased returned word → original input spelling.
        var inputByLower: [String: String] = [:]
        for w in words { inputByLower[w.lowercased()] = w }
        var result: [String: WordCard] = [:]
        for entry in entries {
            let lower = entry.word.lowercased()
            guard !lower.isEmpty else { continue }
            result[inputByLower[lower] ?? lower] = entry.card
        }
        return result
    }

    private func callAndDecode<T: Decodable>(_ type: T.Type, prompt: String, model: String? = nil) async throws -> T {
        let useModel = model ?? settings.model
        activity?.begin()
        defer { activity?.end() }
        do {
            let raw = try await runner.run(prompt: prompt, model: useModel)
            return try JSONCleaning.decode(T.self, from: raw)
        } catch let error as AgyError {
            // Only decode failures are retryable; transport errors (timeout,
            // non-zero exit) propagate immediately so no entry/quota is written.
            guard case .decodeFailure = error, shouldRetry else { throw error }
            let raw = try await runner.run(prompt: prompt, model: useModel)
            return try JSONCleaning.decode(T.self, from: raw)
        }
    }

    private var shouldRetry: Bool {
        switch settings.jsonErrorBehavior {
        case .retryOnce, .askAgain: return true
        case .showRaw: return false
        }
    }
}
