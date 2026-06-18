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
        return value ?? []
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
    public var ipa: String?
    public var pos: String?
    public var meaningVi: String?
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

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: GenericKey.self)
        ipa = decodeString(c, "ipa")
        pos = decodeString(c, "pos")
        meaningVi = decodeString(c, "meaningVi")
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
    }

    /// Returns a copy where each field keeps `self`'s value when present, else
    /// takes `other`'s (used to fold lazy enrichment into a core card).
    public func merging(_ other: WordCard) -> WordCard {
        func pick(_ a: String?, _ b: String?) -> String? { (a?.isEmpty == false) ? a : b }
        var c = self
        c.ipa = pick(ipa, other.ipa); c.pos = pick(pos, other.pos)
        c.meaningVi = pick(meaningVi, other.meaningVi); c.meaningEn = pick(meaningEn, other.meaningEn)
        c.etymology = pick(etymology, other.etymology); c.cefrLevel = pick(cefrLevel, other.cefrLevel)
        c.register = pick(register, other.register); c.frequency = pick(frequency, other.frequency)
        if examples.isEmpty { c.examples = other.examples }
        if synonyms.isEmpty { c.synonyms = other.synonyms }
        if antonyms.isEmpty { c.antonyms = other.antonyms }
        if wordFamily.isEmpty { c.wordFamily = other.wordFamily }
        if collocations.isEmpty { c.collocations = other.collocations }
        if confusables.isEmpty { c.confusables = other.confusables }
        c.category = pick(category, other.category)
        return c
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
    public var meaningVi: String?
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

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: GenericKey.self)
        type = decodeString(c, "type")
        formulaPattern = decodeString(c, "formulaPattern")
        patternConfidence = decodeDouble(c, "patternConfidence")
        meaningVi = decodeString(c, "meaningVi")
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
    }

    /// Returns a copy where each field keeps `self`'s value when present, else
    /// takes `other`'s (folds lazy enrichment into a core phrase card).
    public func merging(_ other: PhraseCard) -> PhraseCard {
        func pick(_ a: String?, _ b: String?) -> String? { (a?.isEmpty == false) ? a : b }
        var c = self
        c.type = pick(type, other.type); c.formulaPattern = pick(formulaPattern, other.formulaPattern)
        c.patternConfidence = patternConfidence ?? other.patternConfidence
        c.meaningVi = pick(meaningVi, other.meaningVi); c.meaningEn = pick(meaningEn, other.meaningEn)
        c.register = pick(register, other.register); c.cefrLevel = pick(cefrLevel, other.cefrLevel)
        c.separable = separable ?? other.separable
        c.objectType = pick(objectType, other.objectType); c.usageNote = pick(usageNote, other.usageNote)
        if examples.isEmpty { c.examples = other.examples }
        if variations.isEmpty { c.variations = other.variations }
        if commonErrors.isEmpty { c.commonErrors = other.commonErrors }
        if relatedPhrases.isEmpty { c.relatedPhrases = other.relatedPhrases }
        c.category = pick(category, other.category)
        return c
    }
}

/// One vocabulary item extracted from a paragraph (SPEC §7c).
public struct ParagraphItem: Codable, Sendable, Equatable {
    public var word: String?
    public var cefr: String?
    public var pos: String?
    public var meaningVi: String?
    public var reasonToLearn: String?
    public var category: String?

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: GenericKey.self)
        word = decodeString(c, "word")
        cefr = decodeString(c, "cefr")
        pos = decodeString(c, "pos")
        meaningVi = decodeString(c, "meaningVi")
        reasonToLearn = decodeString(c, "reasonToLearn")
        category = decodeString(c, "category")
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
            diff = value ?? []
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
