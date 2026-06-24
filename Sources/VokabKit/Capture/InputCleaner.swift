import Foundation

/// Canonical cleaning for captured text, run right after classification and
/// before dedup / cache / agy / persist (SPEC §6, §9, §11).
///
/// - word / phrase: strip leading & trailing whitespace **and** Unicode
///   punctuation (quotes, brackets, `.,;:!?…`, hyphen, `¿¡`, smart
///   quotes), then collapse internal whitespace to single spaces. Case is
///   preserved; internal punctuation (`don't`, `co-op`) is untouched. Symbols
///   (`$ + = < >`) are NOT punctuation and survive at the edges. Note: `&`,
///   `#`, `%`, `@`, `/`, `*` **are** Unicode punctuation and ARE stripped at
///   the edges (unlike the math/currency symbols `$ + = < >`).
/// - paragraph: only whitespace-trim the edges — punctuation is needed for
///   sentence splitting downstream.
///
/// May return `""` when the input is pure punctuation (e.g. `"...,"`); callers
/// must treat an empty result as "nothing to capture".
public enum InputCleaner {
    private static let edgeSet = CharacterSet.whitespacesAndNewlines
        .union(.punctuationCharacters)

    public static func clean(_ text: String, type: CardType) -> String {
        switch type {
        case .paragraphItem:
            return text.trimmingCharacters(in: .whitespacesAndNewlines)
        case .word, .phrase:
            return text
                .trimmingCharacters(in: edgeSet)
                .components(separatedBy: .whitespacesAndNewlines)
                .filter { !$0.isEmpty }
                .joined(separator: " ")
        }
    }
}
