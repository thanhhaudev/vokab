import Foundation
import NaturalLanguage

/// Classifies captured text into a `CardType` (SPEC §6). Word counting uses
/// `NLTokenizer` so it works for languages without spaces (Japanese, Chinese,
/// Thai) — a whitespace split would treat a whole CJK sentence as one "word".
public enum InputClassifier {

    public static func classify(_ text: String) -> CardType {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return .word }

        // Multiple sentences (Latin or CJK terminators followed by more text).
        if trimmed.range(of: "[.!?。！？；;]\\s*\\S", options: .regularExpression) != nil {
            return .paragraphItem
        }

        let words = wordCount(trimmed)
        if words <= 1 { return .word }
        if words <= 6 { return .phrase }
        return .paragraphItem
    }

    /// Language-agnostic word count (segments CJK correctly).
    private static func wordCount(_ text: String) -> Int {
        let tokenizer = NLTokenizer(unit: .word)
        tokenizer.string = text
        var count = 0
        tokenizer.enumerateTokens(in: text.startIndex..<text.endIndex) { _, _ in
            count += 1
            return true
        }
        return count
    }
}
