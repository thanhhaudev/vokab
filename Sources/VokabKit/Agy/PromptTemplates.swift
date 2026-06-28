import Foundation

/// The four agy prompt templates (SPEC §7). Every template demands pure JSON
/// with no preamble or markdown fence; `JSONCleaning` strips fences defensively.
public enum PromptTemplates {

    /// Single word (SPEC §7a).
    public static func word(_ word: String, language: String, meaningLanguage: String) -> String {
        """
        Define '\(word)' (language: \(language)). Return ONLY JSON:
        {ipa, senses:[{pos, meaning, meaning_en, examples[], matches_context}],
         etymology, cefr_level, register, frequency, synonyms[], antonyms[], word_family[]}
        List ALL common senses of the word, one object per sense in "senses".
        "meaning" = that sense's definition in \(meaningLanguage); "meaning_en" = in English.
        "matches_context": set true only on the sense matching a provided context sentence;
        with no sentence given, set it false on every sense.
        No preamble, no markdown fence.
        """
    }

    /// Phrase / idiom (SPEC §7b).
    public static func phrase(_ phrase: String, meaningLanguage: String) -> String {
        """
        Analyze the phrase '\(phrase)'. Return ONLY JSON:
        {type, formula_pattern, pattern_confidence, meaning, meaning_en,
         register, cefr_level, separable, object_type, usage_note,
         examples[], variations[], common_errors[], related_phrases[]}
        "meaning" = the definition in \(meaningLanguage); "meaning_en" = the definition in English.
        "meaning" and "meaning_en" are REQUIRED — always include both, never omit
        them, even for long, slang, or vulgar phrases.
        No preamble, no markdown fence.
        """
    }

    /// Paragraph extraction (SPEC §7c) — returns an exhaustive list of
    /// worth-learning items, each with a category. The whole-passage translation is
    /// fetched separately/in the background so the item list can render immediately.
    public static func paragraph(_ paragraph: String, minLevel: CEFR, meaningLanguage: String, taxonomy: [String]) -> String {
        """
        Analyze this text for a \(meaningLanguage)-speaking learner of English. Return ONLY JSON:
        {"items": [{word, cefr, pos, meaning, reason_to_learn, category}]}
        "meaning" = the word's meaning in \(meaningLanguage).

        For "items": list EVERY word or short phrase worth learning at CEFR \(minLevel.rawValue.uppercased()) or above.
        Give each "word" as its dictionary HEADWORD (lemma) — e.g. write 'run' for an occurrence of 'running',
        'child' for 'children' — UNLESS the inflected form is itself a distinct dictionary entry
        (e.g. 'interesting', 'glasses'), in which case keep that form.
        Be exhaustive — do NOT cap the count, do NOT omit items, do NOT summarize.
        Filter out only basic words (A1–A2 below the minimum).
        For each "category": prefer reusing one of [\(taxonomy.joined(separator: ", "))]; only invent a new one if none fits.
        Category MUST be human-readable Title Case (e.g. "Social media"), never snake_case or kebab-case.

        Text:
        \(paragraph)

        No preamble, no markdown fence.
        """
    }

    /// Lightweight classify-only prompt for lazy backfill of Phase-1 entries.
    public static func classify(_ text: String, language: String, taxonomy: [String]) -> String {
        """
        For '\(text)' (language: \(language)) pick the single best category.
        Prefer reusing one of [\(taxonomy.joined(separator: ", "))]; only invent a new one if none fits.
        Category MUST be human-readable Title Case (e.g. "Social media"), never snake_case or kebab-case.
        Return ONLY JSON: {category}
        No preamble, no markdown fence.
        """
    }

    /// Word — core fields only (capture, fast). Carries the current taxonomy so
    /// agy reuses existing categories before inventing one (Phase 2).
    public static func wordCore(_ word: String, language: String, meaningLanguage: String, taxonomy: [String]) -> String {
        """
        Define the captured text '\(word)' (language: \(language)). Return ONLY JSON:
        {headword, ipa, senses:[{pos, meaning, meaning_en, examples[], matches_context}], cefr_level, register, category}
        "headword" = the dictionary HEADWORD (lemma) of '\(word)' — e.g. 'running'->'run', 'ran'->'run', 'cats'->'cat'.
        BUT if '\(word)' is itself a distinct dictionary entry with its own part of speech or meaning
        (e.g. 'interesting' adjective, 'glasses' meaning spectacles, 'developed' as in 'developed country'),
        set "headword" to '\(word)' unchanged. Then DEFINE that headword: every other field describes the headword.
        List ALL common senses of the headword, one object per sense; give exactly one short example per sense.
        "meaning" = that sense's definition in \(meaningLanguage); "meaning_en" = in English.
        "matches_context": false on every sense (no context sentence is supplied here).
        For "category": prefer reusing one of [\(taxonomy.joined(separator: ", "))]; only invent a new one if none fits.
        Category MUST be human-readable Title Case (e.g. "Social media"), never snake_case or kebab-case.
        No preamble, no markdown fence.
        """
    }

    /// Word enrichment, part A (extras) — runs in parallel with B.
    public static func wordEnrichExtras(_ word: String, language: String) -> String {
        """
        For '\(word)' (language: \(language)) return ONLY JSON:
        {etymology, frequency, examples[]}
        examples[] = 2 example sentences. No preamble, no markdown fence.
        """
    }

    /// Word enrichment, part B (relations) — runs in parallel with A.
    public static func wordEnrichRelations(_ word: String, language: String) -> String {
        """
        For '\(word)' (language: \(language)) return ONLY JSON:
        {synonyms[], antonyms[], word_family[], collocations[], confusables[], forms[], irregular, context_of_use, grammar_note}
        collocations[] = 3–5 common collocations (e.g. "make a decision").
        confusables[] = [{word, note_vi}] easily-confused words, each with a short Vietnamese note on the difference.
        forms[] = the word's inflected forms as [{label, form}], POS-appropriate
          (verb: past, past participle, -ing, 3rd-person; noun: plural;
           adjective: comparative, superlative). Omit forms that don't apply
           (uncountable nouns, invariable words). Use SHORT human labels.
        irregular = true if any form is irregular (e.g. ran/run, good/better), else false.
        context_of_use: 1–2 sentence Vietnamese learner note on the situation/context to use this word (formal/informal nuance, domain, when/where).
        grammar_note: 1–2 sentence Vietnamese note on grammar/tense (for verbs: tenses typically used in, irregular forms; for nouns: countable/uncountable).
        No preamble, no markdown fence.
        """
    }

    /// Batched word enrichment, part A (extras) — one agy call for many words.
    /// Returns a JSON ARRAY; each element mirrors `wordEnrichExtras` plus the
    /// exact input `word` so callers can key the result.
    public static func wordExtrasBatch(words: [String], language: String) -> String {
        let list = words.map { "\"\($0)\"" }.joined(separator: ", ")
        return """
        For EACH of these words (language: \(language)): [\(list)]
        return ONLY a JSON ARRAY, one object per word:
        [{word, etymology, frequency, examples[]}]
        "word" MUST be the exact input word. examples[] = 2 example sentences.
        No preamble, no markdown fence.
        """
    }

    /// Batched word enrichment, part B (relations) — one agy call for many words.
    /// Returns a JSON ARRAY; each element mirrors `wordEnrichRelations` plus the
    /// exact input `word`.
    public static func wordRelationsBatch(words: [String], language: String) -> String {
        let list = words.map { "\"\($0)\"" }.joined(separator: ", ")
        return """
        For EACH of these words (language: \(language)): [\(list)]
        return ONLY a JSON ARRAY, one object per word:
        [{word, synonyms[], antonyms[], word_family[], collocations[], confusables[], forms[], irregular, context_of_use, grammar_note}]
        "word" MUST be the exact input word.
        collocations[] = 3–5 common collocations (e.g. "make a decision").
        confusables[] = [{word, note_vi}] easily-confused words, each with a short Vietnamese note on the difference.
        forms[] = the word's inflected forms as [{label, form}], POS-appropriate
          (verb: past, past participle, -ing, 3rd-person; noun: plural;
           adjective: comparative, superlative). Omit forms that don't apply
           (uncountable nouns, invariable words). Use SHORT human labels.
        irregular = true if any form is irregular (e.g. ran/run, good/better), else false.
        context_of_use: 1–2 sentence Vietnamese learner note on the situation/context to use this word (formal/informal nuance, domain, when/where).
        grammar_note: 1–2 sentence Vietnamese note on grammar/tense (for verbs: tenses typically used in, irregular forms; for nouns: countable/uncountable).
        No preamble, no markdown fence.
        """
    }

    /// Lightweight backfill of just the two newer relation fields for entries
    /// enriched before they existed (analog of `classify`).
    public static func wordRelationsBackfill(_ word: String, language: String) -> String {
        """
        For '\(word)' (language: \(language)) return ONLY JSON:
        {collocations[], confusables[], forms[], irregular, context_of_use, grammar_note}
        collocations[] = 3–5 common collocations (e.g. "make a decision").
        confusables[] = [{word, note_vi}] easily-confused words, each with a short Vietnamese note on the difference.
        forms[] = the word's inflected forms as [{label, form}], POS-appropriate
          (verb: past, past participle, -ing, 3rd-person; noun: plural;
           adjective: comparative, superlative). Omit forms that don't apply
           (uncountable nouns, invariable words). Use SHORT human labels.
        irregular = true if any form is irregular (e.g. ran/run, good/better), else false.
        context_of_use: 1–2 sentence Vietnamese learner note on the situation/context to use this word (formal/informal nuance, domain, when/where).
        grammar_note: 1–2 sentence Vietnamese note on grammar/tense (for verbs: tenses typically used in, irregular forms; for nouns: countable/uncountable).
        No preamble, no markdown fence.
        """
    }

    /// Phrase — core fields only (capture).
    public static func phraseCore(_ phrase: String, meaningLanguage: String, taxonomy: [String]) -> String {
        """
        Analyze the phrase '\(phrase)'. Return ONLY JSON:
        {type, formula_pattern, pattern_confidence, meaning, meaning_en, register, cefr_level, examples[], category}
        "meaning" = the definition in \(meaningLanguage); "meaning_en" = the definition in English.
        Give exactly one short example.
        For "category": prefer reusing one of [\(taxonomy.joined(separator: ", "))]; only invent a new one if none fits.
        Category MUST be human-readable Title Case (e.g. "Social media"), never snake_case or kebab-case.
        No preamble, no markdown fence.
        """
    }

    /// Phrase enrichment, part A (usage) — parallel with B.
    public static func phraseEnrichExtras(_ phrase: String) -> String {
        """
        For the phrase '\(phrase)' return ONLY JSON:
        {separable, object_type, usage_note, examples[]}
        examples[] = 2 examples. No preamble, no markdown fence.
        """
    }

    /// Phrase enrichment, part B (relations) — parallel with A.
    public static func phraseEnrichRelations(_ phrase: String) -> String {
        """
        For the phrase '\(phrase)' return ONLY JSON:
        {variations[], common_errors[], related_phrases[], context_of_use, grammar_note}
        common_errors[] = [{sentence, answer, options[], note_vi}] where sentence
        contains "_____" at the error position, answer is the correct span, options
        is 3–4 choices including answer + the common wrong form, note_vi is a short
        Vietnamese explanation.
        context_of_use: 1–2 sentence Vietnamese learner note on the situation/context to use this phrase (formal/informal nuance, domain, when/where).
        grammar_note: 1–2 sentence Vietnamese note on the grammatical pattern and tense this phrase is typically used in.
        No preamble, no markdown fence.
        """
    }

    /// Lightweight backfill of just the structured common_errors for phrases
    /// enriched before they existed (analog of `wordRelationsBackfill`).
    public static func phraseErrorsBackfill(_ phrase: String) -> String {
        """
        For the phrase '\(phrase)' return ONLY JSON:
        {common_errors[], context_of_use, grammar_note}
        common_errors[] = [{sentence, answer, options[], note_vi}] where sentence
        contains "_____" at the error position, answer is the correct span, options
        is 3–4 choices including answer + the common wrong form, note_vi is a short
        Vietnamese explanation.
        context_of_use: 1–2 sentence Vietnamese learner note on the situation/context to use this phrase (formal/informal nuance, domain, when/where).
        grammar_note: 1–2 sentence Vietnamese note on the grammatical pattern and tense this phrase is typically used in.
        No preamble, no markdown fence.
        """
    }

    /// Backfill just the core meaning for phrases whose analysis dropped it (the
    /// model sometimes omits `meaning`/`meaning_en` for long/slang/vulgar phrases).
    public static func phraseMeaningBackfill(_ phrase: String, meaningLanguage: String) -> String {
        """
        For the phrase '\(phrase)' return ONLY JSON:
        {meaning, meaning_en}
        "meaning" = the definition in \(meaningLanguage); "meaning_en" = the definition in English.
        Both are REQUIRED — never omit either, even for long, slang, or vulgar phrases.
        No preamble, no markdown fence.
        """
    }

    /// Generate additional example sentences for a phrase, on demand (the "+" in
    /// the phrase detail's Examples section). Steers away from the ones already shown.
    public static func phraseMoreExamples(_ phrase: String, existing: [String]) -> String {
        let shown = existing.isEmpty ? "(none yet)" : existing.map { "- \($0)" }.joined(separator: "\n")
        return """
        For the phrase '\(phrase)' return ONLY JSON:
        {examples[]}
        examples[] = 2 NEW, natural example sentences that use the phrase, each in a
        DIFFERENT context. They MUST be different from these already shown:
        \(shown)
        No preamble, no markdown fence.
        """
    }

    /// Generate additional example sentences for a single word, on demand (the
    /// "+" in the word detail's Examples section). Steers away from existing ones.
    public static func wordMoreExamples(_ word: String, language: String, existing: [String]) -> String {
        let shown = existing.isEmpty ? "(none yet)" : existing.map { "- \($0)" }.joined(separator: "\n")
        return """
        For the word '\(word)' (language: \(language)) return ONLY JSON:
        {examples[]}
        examples[] = 2 NEW, natural example sentences that use the word, each in a
        DIFFERENT context. They MUST be different from these already shown:
        \(shown)
        No preamble, no markdown fence.
        """
    }

    /// Translate an English sentence into `language` (a language name, e.g. "Vietnamese").
    public static func translate(_ text: String, language: String) -> String {
        """
        Translate this English sentence into \(language), naturally. Return ONLY JSON: {"translation": "..."}.
        No preamble, no markdown fence.
        Sentence: \(text)
        """
    }

    /// Production / writing judgement (SPEC §7d).
    public static func production(word: String, sentence: String, senseMeaning: String? = nil) -> String {
        let target = senseMeaning.map { " (meaning: '\($0)')" } ?? ""
        return """
        The user wrote this sentence to practise '\(word)'\(target): '\(sentence)'.
        Judge grammar & naturalness. Return ONLY JSON:
        {verdict: 'correct'|'minor_error'|'wrong',
         corrected_sentence,
         diff: [{type: 'keep'|'del'|'ins', text}],
         explanation_vi,
         suggested_rating: 'again'|'hard'|'good'|'easy'}
        No preamble, no markdown fence.
        """
    }
}
