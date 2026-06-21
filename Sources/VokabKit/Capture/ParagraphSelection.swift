import Foundation

/// Chooses which extracted paragraph items are checked by default: everything
/// not already in the library (dedupe), matched on normalized word (SPEC §11).
public enum ParagraphSelection {
    /// `existingNormalized` = normalized words already saved. Returns the normalized
    /// word keys for items that should start checked (new words only).
    public static func defaultSelection(items: [ParagraphItem], existingNormalized: Set<String>) -> Set<String> {
        var selected = Set<String>()
        for item in items {
            let key = TextKey.normalize(item.word ?? "")
            if !key.isEmpty && !existingNormalized.contains(key) { selected.insert(key) }
        }
        return selected
    }
}
