import Foundation

/// Tokenizes a sentence and finds spans of consecutive word tokens that match a
/// known multi-word phrase — used to underline whole phrases (e.g. `ran out of`)
/// inside an example sentence on the detail screen. Pure, no I/O.
public enum PhraseSpanMatcher {
    /// A maximal run of word characters or of non-word characters, in order.
    public struct Atom: Equatable, Sendable {
        public let text: String
        public let isWord: Bool
        public init(text: String, isWord: Bool) { self.text = text; self.isWord = isWord }
    }

    /// Split into word vs non-word atoms (same rule as `ParagraphHighlighter`).
    public static func atoms(_ source: String) -> [Atom] {
        var result: [Atom] = []
        var buffer = ""
        var bufferIsWord = false
        func flush() {
            guard !buffer.isEmpty else { return }
            result.append(Atom(text: buffer, isWord: bufferIsWord))
            buffer = ""
        }
        for ch in source {
            let isWordChar = ch.isLetter || ch.isNumber
            if !buffer.isEmpty && isWordChar != bufferIsWord { flush() }
            bufferIsWord = isWordChar
            buffer.append(ch)
        }
        flush()
        return result
    }

    /// Non-overlapping index ranges over `words` that match a multi-word phrase as
    /// a contiguous subsequence. Single-word phrases are ignored (rendered as plain
    /// words). Longer phrases win; per-word matching is lenient: exact, or a ≥4-char
    /// prefix either direction (so `ran`/`runs` matches `run`).
    public static func spans(words: [String], phrases: [String]) -> [Range<Int>] {
        let phraseWordLists: [[String]] = phrases
            .map { $0.lowercased().split { !($0.isLetter || $0.isNumber) }.map(String.init) }
            .filter { $0.count >= 2 }
        guard !phraseWordLists.isEmpty, !words.isEmpty else { return [] }
        let lowerWords = words.map { $0.lowercased() }
        let ordered = phraseWordLists.sorted { $0.count > $1.count }   // longest first
        var spans: [Range<Int>] = []
        var i = 0
        while i < lowerWords.count {
            var matched: Range<Int>?
            for pw in ordered {
                let end = i + pw.count
                guard end <= lowerWords.count else { continue }
                var ok = true
                for k in 0..<pw.count where !wordMatches(lowerWords[i + k], pw[k]) { ok = false; break }
                if ok { matched = i..<end; break }
            }
            if let m = matched { spans.append(m); i = m.upperBound } else { i += 1 }
        }
        return spans
    }

    /// Lenient single-word match: exact, or prefix/stem match.
    /// Allows: exact match, OR prefix match when at least one is >= 3 chars,
    /// OR Levenshtein distance <= 1 when both are >= 3 chars (for verb conjugations like ran/run).
    static func wordMatches(_ token: String, _ needle: String) -> Bool {
        let t = token.lowercased(), n = needle.lowercased()
        if t == n { return true }
        // Prefix match: at least one is >= 3 chars and one is prefix of other
        if (n.count >= 3 || t.count >= 3) && (t.hasPrefix(n) || n.hasPrefix(t)) { return true }
        // Lenient stem match: both >= 3 chars and Levenshtein distance <= 1
        if t.count >= 3 && n.count >= 3 && levenshteinDistance(t, n) <= 1 { return true }
        return false
    }

    /// Levenshtein distance between two strings.
    static func levenshteinDistance(_ s1: String, _ s2: String) -> Int {
        let s1 = Array(s1), s2 = Array(s2)
        let m = s1.count, n = s2.count
        var dp = Array(repeating: Array(repeating: 0, count: n + 1), count: m + 1)
        for i in 0...m { dp[i][0] = i }
        for j in 0...n { dp[0][j] = j }
        for i in 1...m {
            for j in 1...n {
                if s1[i-1] == s2[j-1] {
                    dp[i][j] = dp[i-1][j-1]
                } else {
                    dp[i][j] = 1 + min(dp[i-1][j], dp[i][j-1], dp[i-1][j-1])
                }
            }
        }
        return dp[m][n]
    }
}
