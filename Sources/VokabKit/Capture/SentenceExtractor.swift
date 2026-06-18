import Foundation

/// Finds the sentence within a source text that contains a target term, used to
/// store the original context a learner met a word in (Phase 3 · E).
///
/// Boundary detection is heuristic (abbreviations like "Mr." may over-split) and
/// matching is lenient; like `ParagraphHighlighter` this is a display aid, not a
/// source of truth, so occasional imperfect splits are acceptable.
public enum SentenceExtractor {

    /// The trimmed sentence within `source` containing `needle`, or nil when not
    /// found or when `source` is itself just the term (no surrounding context).
    public static func extractSentence(containing needle: String, from source: String) -> String? {
        let target = needle.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !target.isEmpty else { return nil }

        for raw in sentences(in: source) {
            let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { continue }
            if trimmed.lowercased() == target { return nil }   // bare term = no context
            if contains(trimmed, needle: target) { return trimmed }
        }
        return nil
    }

    /// Splits on sentence terminators (Latin + CJK) and newlines, keeping each
    /// terminator with its sentence.
    private static func sentences(in source: String) -> [String] {
        let terminators: Set<Character> = [".", "!", "?", "…", "。", "！", "？", "\n"]
        var result: [String] = []
        var buffer = ""
        for ch in source {
            buffer.append(ch)
            if terminators.contains(ch) {
                result.append(buffer)
                buffer = ""
            }
        }
        if !buffer.isEmpty { result.append(buffer) }
        return result
    }

    /// Lenient containment: a multi-word needle uses case-insensitive substring;
    /// a single word matches a token exactly, or by a ≥4-char prefix so a base
    /// form matches an inflection (`exacerbate` → `exacerbated`).
    private static func contains(_ sentence: String, needle: String) -> Bool {
        if needle.contains(" ") {
            return sentence.lowercased().contains(needle)
        }
        let tokens = sentence.lowercased().split { !($0.isLetter || $0.isNumber) }.map(String.init)
        for t in tokens {
            if t == needle { return true }
            if needle.count >= 4 && t.count >= 4 && (t.hasPrefix(needle) || needle.hasPrefix(t)) { return true }
        }
        return false
    }
}
