import Foundation

/// Unions paragraph-extraction item lists by normalized word. Used to accumulate
/// results when the extraction screen lowers its Min-level filter: previously
/// detected words (and the user's checkmarks) are preserved, only genuinely new
/// words are appended (SPEC §11, paragraph fixes).
public enum ParagraphMerge {
    public static func union(_ existing: [ParagraphItem], _ incoming: [ParagraphItem]) -> [ParagraphItem] {
        var result: [ParagraphItem] = []
        var seen = Set<String>()
        for item in existing + incoming {
            let key = TextKey.normalize(item.word ?? "")
            guard !key.isEmpty, !seen.contains(key) else { continue }
            seen.insert(key)
            result.append(item)
        }
        return result
    }
}
