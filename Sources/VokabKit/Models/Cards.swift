import Foundation

// agy returns snake_case JSON. All structs here are decoded with a
// `.convertFromSnakeCase` key strategy (see `JSONCleaning.makeDecoder`), so
// properties are camelCase with no explicit CodingKeys.
//
// Fields are deliberately lenient: scalars are optional and arrays default to
// empty. agy is an LLM, so an occasional missing/extra key must not break a
// capture. UI degrades gracefully on nil.

/// Helper to decode an optional array, defaulting to empty when absent or null.
private func decodeArray(_ container: KeyedDecodingContainer<GenericKey>, _ key: String) -> [String] {
    let k = GenericKey(stringValue: key)!
    if let value = try? container.decodeIfPresent([String].self, forKey: k) {
        return value
    }
    return []
}

private func decodeString(_ container: KeyedDecodingContainer<GenericKey>, _ key: String) -> String? {
    guard let k = GenericKey(stringValue: key) else { return nil }
    return (try? container.decodeIfPresent(String.self, forKey: k)) ?? nil
}

private func decodeDouble(_ container: KeyedDecodingContainer<GenericKey>, _ key: String) -> Double? {
    guard let k = GenericKey(stringValue: key) else { return nil }
    return (try? container.decodeIfPresent(Double.self, forKey: k)) ?? nil
}

private func decodeBool(_ container: KeyedDecodingContainer<GenericKey>, _ key: String) -> Bool? {
    guard let k = GenericKey(stringValue: key) else { return nil }
    return (try? container.decodeIfPresent(Bool.self, forKey: k)) ?? nil
}

/// Picks the gloss to display for the active meaning language `code`. Prefers a
/// `meaning` tagged for that language (or untagged — assumed to match what was
/// requested at capture), otherwise falls back to the English reference. Never
/// shows a gloss in the wrong language (e.g. a legacy Vietnamese entry while the
/// user is in Spanish mode → English).
func resolveMeaning(meaning: String?, lang: String?, meaningEn: String?, for code: String) -> String? {
    func nonEmpty(_ s: String?) -> String? { (s?.isEmpty == false) ? s : nil }
    // `meaning` is usable for the active language only when its tag matches (or is
    // absent — a fresh gloss is assumed to be in the language it was requested in).
    let matches = (lang == nil || lang == code)
    if code == "en" {
        return nonEmpty(meaningEn) ?? (matches ? nonEmpty(meaning) : nil)
    }
    if matches, let m = nonEmpty(meaning) { return m }
    // Active language unavailable → English reference; never a known wrong-language gloss.
    return nonEmpty(meaningEn)
}

/// Dynamic coding key so decoding is tolerant of whatever keys appear.
struct GenericKey: CodingKey {
    var stringValue: String
    var intValue: Int? { nil }
    init?(stringValue: String) { self.stringValue = stringValue }
    init?(intValue: Int) { nil }
}

/// An easily-confused word with a short Vietnamese note on the difference.
public struct Confusable: Codable, Sendable, Equatable {
    public var word: String
    public var noteVi: String?

    public init(word: String, noteVi: String? = nil) {
        self.word = word
        self.noteVi = noteVi
    }

    // Lenient: a missing `word` decodes to "" (filtered out by WordCard); the
    // decoder's `.convertFromSnakeCase` maps `note_vi` → `noteVi`.
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: GenericKey.self)
        word = decodeString(c, "word") ?? ""
        noteVi = decodeString(c, "noteVi")
    }
}

/// Single-word analysis (SPEC §7a).
public struct WordCard: Codable, Sendable, Equatable {
    /// One part-of-speech sense of a word (SPEC: multi-sense words).
    public struct Sense: Codable, Sendable, Equatable {
        public var pos: String?
        public var meaning: String?
        public var meaningEn: String?
        public var examples: [String]
        /// True for the single sense matching the captured sentence's context;
        /// false when no context sentence was supplied.
        public var matchesContext: Bool

        public init(pos: String? = nil, meaning: String? = nil, meaningEn: String? = nil,
                    examples: [String] = [], matchesContext: Bool = false) {
            self.pos = pos; self.meaning = meaning; self.meaningEn = meaningEn
            self.examples = examples; self.matchesContext = matchesContext
        }

        public init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: GenericKey.self)
            pos = decodeString(c, "pos")
            meaning = decodeString(c, "meaning")
            meaningEn = decodeString(c, "meaningEn")
            examples = decodeArray(c, "examples")
            matchesContext = ((try? c.decodeIfPresent(Bool.self,
                forKey: GenericKey(stringValue: "matchesContext")!)) ?? nil) ?? false
        }
    }

    public var ipa: String?
    public var pos: String?
    public var senses: [Sense]
    /// Primary gloss, in the meaning language active at capture (see `meaningLang`).
    public var meaning: String?
    /// Language code of `meaning` (e.g. "vi", "es"). nil = untagged/legacy.
    public var meaningLang: String?
    public var meaningEn: String?
    public var examples: [String]
    public var etymology: String?
    public var cefrLevel: String?
    public var register: String?
    public var frequency: String?
    public var synonyms: [String]
    public var antonyms: [String]
    public var wordFamily: [String]
    public var collocations: [String]
    public var confusables: [Confusable]
    public var category: String?
    public var contextOfUse: String?
    public var grammarNote: String?

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: GenericKey.self)
        ipa = decodeString(c, "ipa")
        pos = decodeString(c, "pos")
        senses = (try? c.decodeIfPresent([Sense].self,
            forKey: GenericKey(stringValue: "senses")!)) ?? nil ?? []
        meaning = decodeString(c, "meaning") ?? decodeString(c, "meaningVi")   // legacy: meaning_vi
        meaningLang = decodeString(c, "meaningLang") ?? (decodeString(c, "meaningVi") != nil ? "vi" : nil)
        meaningEn = decodeString(c, "meaningEn")
        examples = decodeArray(c, "examples")
        etymology = decodeString(c, "etymology")
        cefrLevel = decodeString(c, "cefrLevel")
        register = decodeString(c, "register")
        frequency = decodeString(c, "frequency")
        synonyms = decodeArray(c, "synonyms")
        antonyms = decodeArray(c, "antonyms")
        wordFamily = decodeArray(c, "wordFamily")
        collocations = decodeArray(c, "collocations")
        let rawConfusables = (try? c.decodeIfPresent([Confusable].self,
                                                      forKey: GenericKey(stringValue: "confusables")!)) ?? nil ?? []
        confusables = rawConfusables.filter { !$0.word.trimmingCharacters(in: .whitespaces).isEmpty }
        category = decodeString(c, "category")
        contextOfUse = decodeString(c, "contextOfUse")
        grammarNote = decodeString(c, "grammarNote")
    }

    /// Returns a copy where each field keeps `self`'s value when present, else
    /// takes `other`'s (used to fold lazy enrichment into a core card).
    public func merging(_ other: WordCard) -> WordCard {
        func pick(_ a: String?, _ b: String?) -> String? { (a?.isEmpty == false) ? a : b }
        var c = self
        c.ipa = pick(ipa, other.ipa); c.pos = pick(pos, other.pos)
        c.meaning = pick(meaning, other.meaning); c.meaningLang = pick(meaningLang, other.meaningLang)
        c.meaningEn = pick(meaningEn, other.meaningEn)
        c.etymology = pick(etymology, other.etymology); c.cefrLevel = pick(cefrLevel, other.cefrLevel)
        c.register = pick(register, other.register); c.frequency = pick(frequency, other.frequency)
        if examples.isEmpty { c.examples = other.examples }
        if synonyms.isEmpty { c.synonyms = other.synonyms }
        if antonyms.isEmpty { c.antonyms = other.antonyms }
        if wordFamily.isEmpty { c.wordFamily = other.wordFamily }
        if collocations.isEmpty { c.collocations = other.collocations }
        if confusables.isEmpty { c.confusables = other.confusables }
        c.category = pick(category, other.category)
        c.contextOfUse = pick(contextOfUse, other.contextOfUse)
        c.grammarNote = pick(grammarNote, other.grammarNote)
        return c
    }

    /// The gloss to display for the active meaning language `code`.
    public func meaning(forLanguage code: String) -> String? {
        resolveMeaning(meaning: meaning, lang: meaningLang, meaningEn: meaningEn, for: code)
    }
}

/// One error-correction quiz item: a sentence with a blank (`ClozeBuilder.blank`)
/// at the error spot, the correct span, tap options, and a Vietnamese note.
public struct ErrorQuiz: Codable, Sendable, Equatable {
    public var sentence: String
    public var answer: String
    public var options: [String]
    public var noteVi: String?

    public init(sentence: String, answer: String, options: [String], noteVi: String? = nil) {
        self.sentence = sentence; self.answer = answer; self.options = options; self.noteVi = noteVi
    }
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: GenericKey.self)
        sentence = decodeString(c, "sentence") ?? ""
        answer = decodeString(c, "answer") ?? ""
        options = decodeArray(c, "options")
        noteVi = decodeString(c, "noteVi")
    }
}

/// Phrase / idiom analysis (SPEC §7b).
public struct PhraseCard: Codable, Sendable, Equatable {
    public var type: String?
    public var formulaPattern: String?
    public var patternConfidence: Double?
    /// Primary gloss, in the meaning language active at capture (see `meaningLang`).
    public var meaning: String?
    /// Language code of `meaning` (e.g. "vi", "es"). nil = untagged/legacy.
    public var meaningLang: String?
    public var meaningEn: String?
    public var register: String?
    public var cefrLevel: String?
    public var separable: Bool?
    public var objectType: String?
    public var usageNote: String?
    public var examples: [String]
    public var variations: [String]
    public var commonErrors: [ErrorQuiz]
    public var relatedPhrases: [String]
    public var category: String?
    public var contextOfUse: String?
    public var grammarNote: String?

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: GenericKey.self)
        type = decodeString(c, "type")
        formulaPattern = decodeString(c, "formulaPattern")
        patternConfidence = decodeDouble(c, "patternConfidence")
        meaning = decodeString(c, "meaning") ?? decodeString(c, "meaningVi")   // legacy: meaning_vi
        meaningLang = decodeString(c, "meaningLang") ?? (decodeString(c, "meaningVi") != nil ? "vi" : nil)
        meaningEn = decodeString(c, "meaningEn")
        register = decodeString(c, "register")
        cefrLevel = decodeString(c, "cefrLevel")
        separable = decodeBool(c, "separable")
        objectType = decodeString(c, "objectType")
        usageNote = decodeString(c, "usageNote")
        examples = decodeArray(c, "examples")
        variations = decodeArray(c, "variations")
        let rawErrors = (try? c.decodeIfPresent([ErrorQuiz].self,
                                                forKey: GenericKey(stringValue: "commonErrors")!)) ?? nil ?? []
        commonErrors = rawErrors.filter { !$0.sentence.isEmpty && !$0.answer.isEmpty }
        relatedPhrases = decodeArray(c, "relatedPhrases")
        category = decodeString(c, "category")
        contextOfUse = decodeString(c, "contextOfUse")
        grammarNote = decodeString(c, "grammarNote")
    }

    /// Returns a copy where each field keeps `self`'s value when present, else
    /// takes `other`'s (folds lazy enrichment into a core phrase card).
    public func merging(_ other: PhraseCard) -> PhraseCard {
        func pick(_ a: String?, _ b: String?) -> String? { (a?.isEmpty == false) ? a : b }
        var c = self
        c.type = pick(type, other.type); c.formulaPattern = pick(formulaPattern, other.formulaPattern)
        c.patternConfidence = patternConfidence ?? other.patternConfidence
        c.meaning = pick(meaning, other.meaning); c.meaningLang = pick(meaningLang, other.meaningLang)
        c.meaningEn = pick(meaningEn, other.meaningEn)
        c.register = pick(register, other.register); c.cefrLevel = pick(cefrLevel, other.cefrLevel)
        c.separable = separable ?? other.separable
        c.objectType = pick(objectType, other.objectType); c.usageNote = pick(usageNote, other.usageNote)
        if examples.isEmpty { c.examples = other.examples }
        if variations.isEmpty { c.variations = other.variations }
        if commonErrors.isEmpty { c.commonErrors = other.commonErrors }
        if relatedPhrases.isEmpty { c.relatedPhrases = other.relatedPhrases }
        c.category = pick(category, other.category)
        c.contextOfUse = pick(contextOfUse, other.contextOfUse)
        c.grammarNote = pick(grammarNote, other.grammarNote)
        return c
    }

    /// The gloss to display for the active meaning language `code`.
    public func meaning(forLanguage code: String) -> String? {
        resolveMeaning(meaning: meaning, lang: meaningLang, meaningEn: meaningEn, for: code)
    }
}

/// One vocabulary item extracted from a paragraph (SPEC §7c).
public struct ParagraphItem: Codable, Sendable, Equatable, Hashable {
    public var word: String?
    public var cefr: String?
    public var pos: String?
    /// Gloss in the meaning language active at extraction (see `meaningLang`).
    public var meaning: String?
    public var meaningLang: String?
    public var reasonToLearn: String?
    public var category: String?

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: GenericKey.self)
        word = decodeString(c, "word")
        cefr = decodeString(c, "cefr")
        pos = decodeString(c, "pos")
        meaning = decodeString(c, "meaning") ?? decodeString(c, "meaningVi")   // legacy: meaning_vi
        meaningLang = decodeString(c, "meaningLang") ?? (decodeString(c, "meaningVi") != nil ? "vi" : nil)
        reasonToLearn = decodeString(c, "reasonToLearn")
        category = decodeString(c, "category")
    }
}

/// Result of a paragraph extraction: a learner-language translation of the whole
/// passage plus the candidate vocabulary items (SPEC §7c, paragraph fixes).
/// Decoded leniently from agy (snake_case `translation_vi`) and from our own
/// cache (camelCase `translationVi`); encode is default-synthesized.
public struct ParagraphExtraction: Codable, Sendable, Equatable {
    public var translationVi: String?
    public var items: [ParagraphItem]

    public init(translationVi: String?, items: [ParagraphItem]) {
        self.translationVi = translationVi
        self.items = items
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: GenericKey.self)
        translationVi = decodeString(c, "translationVi") ?? decodeString(c, "translation_vi")
        if let k = GenericKey(stringValue: "items"),
           let arr = try? c.decode([ParagraphItem].self, forKey: k) {
            items = arr
        } else {
            items = []
        }
    }
}

/// One token in a production-feedback diff (SPEC §7d). `type` is keep|del|ins.
public struct DiffToken: Codable, Sendable, Equatable {
    public var type: String
    public var text: String

    public init(type: String, text: String) {
        self.type = type
        self.text = text
    }
}

/// agy's judgement of a user-written sentence (SPEC §7d).
public struct ProductionFeedback: Codable, Sendable, Equatable {
    public var verdict: String?
    public var correctedSentence: String?
    public var diff: [DiffToken]
    public var explanationVi: String?
    public var suggestedRating: String?

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: GenericKey.self)
        verdict = decodeString(c, "verdict")
        correctedSentence = decodeString(c, "correctedSentence")
        let diffKey = GenericKey(stringValue: "diff")!
        if let value = try? c.decodeIfPresent([DiffToken].self, forKey: diffKey) {
            diff = value
        } else {
            diff = []
        }
        explanationVi = decodeString(c, "explanationVi")
        suggestedRating = decodeString(c, "suggestedRating")
    }

    /// Suggested SM-2 grade parsed from agy's `suggested_rating` string.
    public var suggestedGrade: ReviewGrade? {
        switch suggestedRating?.lowercased() {
        case "again": return .again
        case "hard": return .hard
        case "good": return .good
        case "easy": return .easy
        default: return nil
        }
    }
}
