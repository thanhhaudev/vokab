import SwiftUI
import NaturalLanguage

/// Derives part-of-speech coloring locally (no agy round-trip) so phrase tokens,
/// formula patterns, and etymology pick up the mockup's color language.
enum POSColorizer {

    /// Splits a phrase into words tagged with their lexical class.
    static func taggedWords(_ phrase: String) -> [(text: String, pos: String?)] {
        let tagger = NLTagger(tagSchemes: [.lexicalClass])
        tagger.string = phrase
        var result: [(String, String?)] = []
        let range = phrase.startIndex..<phrase.endIndex
        tagger.enumerateTags(in: range, unit: .word, scheme: .lexicalClass,
                             options: [.omitWhitespace, .omitPunctuation]) { tag, tokenRange in
            result.append((String(phrase[tokenRange]), tag?.rawValue))
            return true
        }
        return result
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
        if pos.hasPrefix("verb") { return (Color(hex: 0x3C3489), Color(hex: 0xEEEDFE)) }
        if pos.hasPrefix("noun") { return (Color(hex: 0x085041), Color(hex: 0xE1F5EE)) }
        if pos.hasPrefix("prep") { return (Color(hex: 0x633806), Color(hex: 0xFAEEDA)) }
        if pos.hasPrefix("adv")  { return (Color(hex: 0x712B13), Color(hex: 0xFAECE7)) }
        return nil
    }
}
