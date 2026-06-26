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
    /// words). Longer phrases win; per-word matching is lenient: case-insensitive exact,
    /// or edit-distance ≤1 for words of 3+ characters (so `ran`/`runs` match `run`).
    /// Longer inflections (e.g. `running`) are intentionally not matched, to avoid false
    /// grouping of short function words.
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

    /// Lenient single-word match: exact, or edit-distance ≤1.
    /// Allows: case-insensitive exact match, OR Levenshtein distance ≤1 when both
    /// are 3+ characters (for verb conjugations like ran/run).
    static func wordMatches(_ token: String, _ needle: String) -> Bool {
        let t = token.lowercased(), n = needle.lowercased()
        if t == n { return true }
        // Levenshtein distance <= 1 for both >= 3 chars (inflections like ran/run/runs)
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

    /// Kind of a render piece for an interactive sentence.
    public enum Kind: String, Sendable, Equatable { case plain, word, phrase }

    /// One render piece: `display` is the original text (with spacing/punctuation),
    /// `lookup` is the text used for the saved-check / capture. `highlighted` marks a
    /// word/phrase piece that matches the optional `highlight` seed (e.g. the headword).
    public struct Piece: Equatable, Sendable {
        public let display: String
        public let lookup: String
        public let kind: Kind
        public let highlighted: Bool
        public init(display: String, lookup: String, kind: Kind, highlighted: Bool = false) {
            self.display = display; self.lookup = lookup; self.kind = kind; self.highlighted = highlighted
        }
    }

    /// True when a word/phrase piece's lookup matches the `highlight` seed: exact
    /// (case-insensitive), or lenient single-word inflection (so `run` matches `runs`).
    private static func isHighlighted(_ lookup: String, _ highlight: String?) -> Bool {
        guard let h = highlight?.trimmingCharacters(in: .whitespaces).lowercased(), !h.isEmpty else { return false }
        let l = lookup.lowercased()
        if l == h { return true }
        if !h.contains(" ") && !l.contains(" ") { return wordMatches(l, h) }
        return false
    }

    /// Splits a sentence into render pieces: known multi-word phrase spans become a
    /// single `.phrase` piece covering ONLY their words + interleaving separators
    /// (trailing punctuation/space stays a separate `.plain` piece); other word
    /// atoms are `.word`; separators are `.plain`. When `highlight` is given, the
    /// word/phrase piece matching it is marked `highlighted` (for headword emphasis).
    public static func pieces(sentence: String, phrases: [String], highlight: String? = nil) -> [Piece] {
        let allAtoms = atoms(sentence)
        var wordIndexOfAtom: [Int?] = []
        var words: [String] = []
        for a in allAtoms {
            if a.isWord { wordIndexOfAtom.append(words.count); words.append(a.text) }
            else { wordIndexOfAtom.append(nil) }
        }
        let foundSpans = spans(words: words, phrases: phrases)
        var spanOfWord: [Int: Range<Int>] = [:]
        for s in foundSpans { for w in s { spanOfWord[w] = s } }

        var result: [Piece] = []
        var i = 0
        while i < allAtoms.count {
            let atom = allAtoms[i]
            if atom.isWord, let wi = wordIndexOfAtom[i], let span = spanOfWord[wi], wi == span.lowerBound {
                // Find the atom index of the span's LAST word; stop there (exclude
                // any trailing separators/punctuation).
                var lastWordAtom = i
                var k = i
                while k < allAtoms.count {
                    if let wk = wordIndexOfAtom[k] {
                        if wk == span.upperBound - 1 { lastWordAtom = k }
                        if wk >= span.upperBound { break }
                    }
                    k += 1
                }
                let display = allAtoms[i...lastWordAtom].map(\.text).joined()
                let lookup = display.trimmingCharacters(in: .whitespaces)
                result.append(Piece(display: display, lookup: lookup, kind: .phrase,
                                    highlighted: isHighlighted(lookup, highlight)))
                i = lastWordAtom + 1
            } else if atom.isWord {
                result.append(Piece(display: atom.text, lookup: atom.text, kind: .word,
                                    highlighted: isHighlighted(atom.text, highlight)))
                i += 1
            } else {
                result.append(Piece(display: atom.text, lookup: atom.text, kind: .plain))
                i += 1
            }
        }
        return result
    }
}
