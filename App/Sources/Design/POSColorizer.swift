import SwiftUI
import NaturalLanguage

/// Derives part-of-speech coloring locally (no agy round-trip) so phrase tokens,
/// formula patterns, and etymology pick up the mockup's color language.
enum POSColorizer {

    /// Splits a phrase into words tagged with their lexical class.
    static func taggedWords(_ phrase: String) -> [(text: String, pos: String?)] {
        let tagger = NLTagger(tagSchemes: [.lexicalClass])
        tagger.string = phrase
        var raw: [(String, String?)] = []
        let range = phrase.startIndex..<phrase.endIndex
        tagger.enumerateTags(in: range, unit: .word, scheme: .lexicalClass,
                             options: [.omitWhitespace, .omitPunctuation]) { tag, tokenRange in
            raw.append((String(phrase[tokenRange]), tag?.rawValue))
            return true
        }
        // NLTagger splits contractions ("I'm" -> "I" + "'m", "don't" -> "do" + "n't").
        // Re-join the trailing fragment into its head word so the phrase reads
        // naturally and we never render an orphan "'m" / "n't" chip.
        var merged: [(String, String?)] = []
        for token in raw {
            if !merged.isEmpty, isContractionSuffix(token.0) {
                merged[merged.count - 1].0 += token.0
            } else {
                merged.append(token)
            }
        }
        // Display casing: sentence-initial capital + always-I.
        if !merged.isEmpty { merged[0].0 = EnglishDisplay.capitalizingFirst(merged[0].0) }
        return merged.map { (EnglishDisplay.fixI($0.0), $0.1) }
    }

    /// A fragment NLTagger split off the head word of a contraction.
    private static func isContractionSuffix(_ token: String) -> Bool {
        token.hasPrefix("'") || token.lowercased() == "n't"
    }

    /// Human-readable name for a colored part of speech, for hover tooltips so a
    /// user can learn what a pill means without external docs. nil for classes
    /// we don't color (rendered as plain text anyway).
    static func posLabel(_ pos: String?) -> String? {
        guard let pos = pos?.lowercased() else { return nil }
        if pos.hasPrefix("verb") { return L.t("verb", "động từ") }
        if pos.hasPrefix("noun") { return L.t("noun", "danh từ") }
        if pos.hasPrefix("prep") { return L.t("preposition", "giới từ") }
        if pos.hasPrefix("adv")  { return L.t("adverb", "trạng từ") }
        return nil
    }

    /// Role keywords in agy formula strings → a part-of-speech bucket for coloring.
    static func formulaRole(_ token: String) -> String? {
        let t = token.lowercased().trimmingCharacters(in: CharacterSet(charactersIn: "()[]"))
        if ["v", "verb", "v-ing", "ving", "v-ed", "do", "doing"].contains(t) { return "verb" }
        if ["n", "noun", "sb", "sth", "sb/sth", "o", "obj"].contains(t) { return "noun" }
        if ["prep", "to", "for", "on", "in", "at", "of", "with", "about"].contains(t) { return "prep" }
        if ["adv", "adverb"].contains(t) { return "adv" }
        return nil
    }

    /// Known source languages to highlight at the head of an etymology string.
    static let languages: Set<String> = [
        "greek", "latin", "french", "german", "spanish", "italian", "arabic",
        "sanskrit", "english", "dutch", "norse", "portuguese", "hebrew", "russian",
        "japanese", "chinese", "celtic", "gaelic", "hindi", "persian", "turkish"
    ]

    static func isLanguage(_ word: String) -> Bool {
        languages.contains(word.lowercased().trimmingCharacters(in: .punctuationCharacters))
    }
}

extension Theme {
    /// Token color for a known part of speech, or nil (render as plain text).
    static func tokenColors(_ pos: String?) -> (fg: Color, bg: Color)? {
        guard let pos = pos?.lowercased() else { return nil }
        if pos.hasPrefix("verb") { return (dyn(light: 0x3C3489, dark: 0xC8C2F5), dyn(light: 0xEEEDFE, dark: 0x2E2A52)) }
        if pos.hasPrefix("noun") { return (dyn(light: 0x085041, dark: 0x6FD3B0), dyn(light: 0xE1F5EE, dark: 0x163A30)) }
        if pos.hasPrefix("prep") { return (dyn(light: 0x633806, dark: 0xE0B978), dyn(light: 0xFAEEDA, dark: 0x3A3322)) }
        if pos.hasPrefix("adv")  { return (dyn(light: 0x712B13, dark: 0xE0A48A), dyn(light: 0xFAECE7, dark: 0x3A2820)) }
        return nil
    }
}
