import AppKit

/// Local spelling check via NSSpellChecker (no network, no quota).
enum SpellCheck {
    struct Issue: Identifiable { let id = UUID(); let word: String; let suggestion: String? }

    /// Misspelled words (with a top suggestion) for `text` in `language` (BCP-47,
    /// e.g. "en"). Returns [] for non-English or when no checker is available, so
    /// callers proceed normally.
    static func issues(in text: String, language: String) -> [Issue] {
        guard language.lowercased().hasPrefix("en") else { return [] }
        let checker = NSSpellChecker.shared
        var found: [Issue] = []
        var seen = Set<String>()
        var start = 0
        let ns = text as NSString
        while start < ns.length {
            let range = checker.checkSpelling(of: text, startingAt: start, language: "en",
                                              wrap: false, inSpellDocumentWithTag: 0, wordCount: nil)
            guard range.location != NSNotFound, range.length > 0 else { break }
            let word = ns.substring(with: range)
            if !seen.contains(word.lowercased()) {
                seen.insert(word.lowercased())
                let guesses = checker.guesses(forWordRange: range, in: text, language: "en",
                                              inSpellDocumentWithTag: 0)
                found.append(Issue(word: word, suggestion: guesses?.first))
            }
            start = range.location + range.length
        }
        return found
    }

    /// Applies the top suggestion for each issue to `text` (whole-word replace).
    static func fixAll(_ text: String, issues: [Issue]) -> String {
        var result = text
        for issue in issues {
            guard let s = issue.suggestion else { continue }
            // word-boundary replace of the misspelled token
            result = result.replacingOccurrences(
                of: "\\b\(NSRegularExpression.escapedPattern(for: issue.word))\\b",
                with: s, options: .regularExpression)
        }
        return result
    }
}
