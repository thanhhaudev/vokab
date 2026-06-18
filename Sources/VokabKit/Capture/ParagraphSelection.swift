import Foundation

/// Chooses which extracted paragraph items are checked by default: everything
/// not already in the library (dedupe), matched on normalized word (SPEC §11).
public enum ParagraphSelection {
    /// `existingNormalized` = normalized words already saved. Returns the indices
    /// into `items` that should start checked.
    public static func defaultSelection(items: [ParagraphItem], existingNormalized: Set<String>) -> Set<Int> {
        var selected = Set<Int>()
        for (i, item) in items.enumerated() {
            let key = TextKey.normalize(item.word ?? "")
            if !key.isEmpty && !existingNormalized.contains(key) { selected.insert(i) }
        }
        return selected
    }
}
