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
        Define '\(word)' (language: \(language)). Return ONLY JSON:
        {ipa, senses:[{pos, meaning, meaning_en, examples[], matches_context}], cefr_level, register, category}
        List ALL common senses, one object per sense; give exactly one short example per sense.
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
        {synonyms[], antonyms[], word_family[], collocations[], confusables[], context_of_use, grammar_note}
        collocations[] = 3–5 common collocations (e.g. "make a decision").
        confusables[] = [{word, note_vi}] easily-confused words, each with a short Vietnamese note on the difference.
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
        [{word, synonyms[], antonyms[], word_family[], collocations[], confusables[], context_of_use, grammar_note}]
        "word" MUST be the exact input word.
        collocations[] = 3–5 common collocations (e.g. "make a decision").
        confusables[] = [{word, note_vi}] easily-confused words, each with a short Vietnamese note on the difference.
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
        {collocations[], confusables[], context_of_use, grammar_note}
        collocations[] = 3–5 common collocations (e.g. "make a decision").
        confusables[] = [{word, note_vi}] easily-confused words, each with a short Vietnamese note on the difference.
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

    /// Translate an English sentence into `language` (a language name, e.g. "Vietnamese").
    public static func translate(_ text: String, language: String) -> String {
        """
        Translate this English sentence into \(language), naturally. Return ONLY JSON: {"translation": "..."}.
        No preamble, no markdown fence.
        Sentence: \(text)
        """
    }

    /// Production / writing judgement (SPEC §7d).
    public static func production(word: String, sentence: String) -> String {
        """
        The user wrote this sentence to practise '\(word)': '\(sentence)'.
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
