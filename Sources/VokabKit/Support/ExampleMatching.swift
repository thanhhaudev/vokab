import Foundation

/// Duplicate detection for on-demand example sentences (the "+" in the word /
/// phrase detail). Comparing raw strings lets near-duplicates slip through —
/// e.g. `"He looks forward to Friday."` vs `"He looks forward to Friday"` differ
/// only in a trailing period yet are the same sentence. Normalizing first
/// (lowercase, collapsed whitespace, no trailing sentence punctuation) catches
/// those. Pure, so it is unit-tested offline.
public enum ExampleMatching {
    /// Normalizes a sentence for comparison: lowercased, trimmed, internal
    /// whitespace runs collapsed to one space, trailing sentence punctuation
    /// (`. ! ? … ；; , :` and quotes) removed. Not for display — comparison only.
    public static func normalized(_ sentence: String) -> String {
        let lowered = sentence.lowercased()
        // Collapse any run of whitespace/newlines to a single space.
        let collapsed = lowered.split(whereSeparator: { $0.isWhitespace }).joined(separator: " ")
        let trailing = CharacterSet(charactersIn: ".!?…;,:\"')]}")
        // Trim trailing punctuation/quotes that don't change the sentence's identity.
        var result = Substring(collapsed)
        while let last = result.unicodeScalars.last, trailing.contains(last) {
            result = result.dropLast()
        }
        return String(result).trimmingCharacters(in: .whitespaces)
    }

    /// True if `candidate` is a normalized duplicate of any entry in `existing`.
    public static func isDuplicate(_ candidate: String, in existing: [String]) -> Bool {
        let key = normalized(candidate)
        guard !key.isEmpty else { return true }   // blank/punctuation-only: treat as dup, never add
        return existing.contains { normalized($0) == key }
    }

    /// Appends only the genuinely new sentences from `more` onto `existing`,
    /// skipping normalized duplicates (including duplicates within `more` itself).
    /// Returns the merged list; identical to `existing` when nothing is new.
    public static func merge(_ existing: [String], adding more: [String]) -> [String] {
        var result = existing
        for candidate in more where !isDuplicate(candidate, in: result) {
            result.append(candidate)
        }
        return result
    }
}
