import Foundation

/// Cheap, local heuristic: does this token clearly NOT look like a real word?
/// Deliberately CONSERVATIVE — only flag obvious keyboard-mash so we never
/// red-flag a legitimate proper noun or technical term. Used only on tokens
/// NSSpellChecker already flagged as misspelled with no suggestion, so the
/// universe is already "weird"; we just separate gibberish from plausible.
public enum WordShape {
    private static let vowels: Set<Character> = ["a", "e", "i", "o", "u"]

    public static func looksLikeGibberish(_ word: String) -> Bool {
        let chars = Array(word.lowercased().filter { $0.isLetter })
        guard chars.count >= 3 else { return false }
        let vowelCount = chars.filter { vowels.contains($0) }.count

        if vowelCount == 0 { return true }                                   // bcdfg
        if maxRun(chars, where: { !vowels.contains($0) }) >= 5 { return true } // asdfgh -> sdfgh
        if maxRepeat(chars) >= 4 { return true }                             // aaaaa
        if chars.count >= 5 && Double(vowelCount) / Double(chars.count) < 0.2 { return true } // qwerty
        return false
    }

    private static func maxRun(_ chars: [Character], where pred: (Character) -> Bool) -> Int {
        var best = 0, cur = 0
        for c in chars { if pred(c) { cur += 1; best = max(best, cur) } else { cur = 0 } }
        return best
    }

    private static func maxRepeat(_ chars: [Character]) -> Int {
        var best = 1, cur = 1
        for i in 1..<chars.count { if chars[i] == chars[i - 1] { cur += 1; best = max(best, cur) } else { cur = 1 } }
        return best
    }
}
