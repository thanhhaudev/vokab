import Foundation

/// Display-only English normalization for user-facing text (phrase tokens,
/// examples, error sentences). agy and captured selections vary in casing, so
/// these helpers make text read naturally without touching what we store.
enum EnglishDisplay {

    /// Uppercases the standalone pronoun "I" and its contractions (I'm, I'll,
    /// I've, I'd) wherever they appear. `\bi\b` catches a lone "i" and, since an
    /// apostrophe is a word boundary, also the "i" in "i'm" / "i'll" / etc.
    static func fixI(_ s: String) -> String {
        s.replacingOccurrences(of: #"\bi\b"#, with: "I", options: .regularExpression)
    }

    /// Capitalizes the first alphabetic character, leaving the rest untouched.
    static func capitalizingFirst(_ s: String) -> String {
        guard let i = s.firstIndex(where: { $0.isLetter }) else { return s }
        return String(s[..<i]) + s[i].uppercased() + String(s[s.index(after: i)...])
    }

    /// Full-sentence display casing: sentence-initial capital + always-I.
    static func sentence(_ s: String) -> String {
        capitalizingFirst(fixI(s))
    }
}
