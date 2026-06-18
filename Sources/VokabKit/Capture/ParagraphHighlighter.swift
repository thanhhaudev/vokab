import Foundation

/// Splits paragraph source text into segments and marks which word tokens match
/// a candidate vocabulary word, so the UI can highlight them (mockup #3 "Source").
///
/// Matching is lenient on purpose — agy returns base forms (`exacerbate`) while
/// the text may be inflected (`exacerbated`): case-insensitive exact match, or a
/// prefix match when both sides are ≥4 chars. This is a display aid, not a source
/// of truth, so occasional misses/over-matches are acceptable.
public enum ParagraphHighlighter {
    public struct Segment: Equatable, Sendable {
        public let text: String
        public let isHighlight: Bool
        public init(text: String, isHighlight: Bool) {
            self.text = text
            self.isHighlight = isHighlight
        }
    }

    public static func segments(source: String, candidates: [String]) -> [Segment] {
        let needles = candidates
            .map { $0.lowercased().trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        var result: [Segment] = []
        var buffer = ""
        var bufferIsWord = false

        func flush() {
            guard !buffer.isEmpty else { return }
            let hl = bufferIsWord && matches(buffer, needles: needles)
            result.append(Segment(text: buffer, isHighlight: hl))
            buffer = ""
        }

        for ch in source {
            let isWordChar = ch.isLetter || ch.isNumber
            if isWordChar != bufferIsWord && !buffer.isEmpty {
                flush()
            }
            bufferIsWord = isWordChar
            buffer.append(ch)
        }
        flush()
        return result
    }

    private static func matches(_ token: String, needles: [String]) -> Bool {
        let t = token.lowercased()
        for n in needles {
            if t == n { return true }
            if n.count >= 4 && t.count >= 4 && (t.hasPrefix(n) || n.hasPrefix(t)) { return true }
        }
        return false
    }
}
