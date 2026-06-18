import Foundation

/// A blanked example sentence and the word/phrase that fills it.
public struct ClozePrompt: Equatable, Sendable {
    public let sentence: String
    public let answer: String
    public init(sentence: String, answer: String) { self.sentence = sentence; self.answer = answer }
}

/// Builds a cloze prompt from the first example sentence that contains the
/// answer. Pure (no I/O) so it is fully unit-testable.
public enum ClozeBuilder {
    /// The placeholder substituted for the answer in `ClozePrompt.sentence`.
    /// Shared so the UI can locate the blank to render (instead of duplicating
    /// the literal).
    public static let blank = "_____"

    /// `answer` is the headword (single word) or full phrase. Returns nil when no
    /// example contains it (caller falls back to recognition).
    public static func build(answer: String, examples: [String], blank: String = ClozeBuilder.blank) -> ClozePrompt? {
        let needle = answer.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !needle.isEmpty else { return nil }
        let wholeWord = !needle.contains(" ")   // single word → require word boundaries
        for example in examples {
            guard let range = matchRange(of: needle, in: example, wholeWord: wholeWord) else { continue }
            return ClozePrompt(sentence: example.replacingCharacters(in: range, with: blank), answer: needle)
        }
        return nil
    }

    /// First match of `needle` in `haystack`, case-insensitive. For a single word
    /// the match is bounded by `\b` so "cat" does not match inside "category".
    private static func matchRange(of needle: String, in haystack: String, wholeWord: Bool) -> Range<String.Index>? {
        if wholeWord {
            let pattern = "\\b" + NSRegularExpression.escapedPattern(for: needle) + "\\b"
            return haystack.range(of: pattern, options: [.regularExpression, .caseInsensitive])
        }
        return haystack.range(of: needle, options: [.caseInsensitive])
    }
}
