import Foundation

/// Client-side CEFR filter for the extraction screen's Min-level control. Raising
/// the level (or any level already fetched) filters the accumulated master list
/// in place — no agy re-scan (SPEC §11, paragraph fixes).
public enum ParagraphFilter {
    /// Keeps items whose CEFR is at or above `minLevel`. Items with a nil or
    /// unrecognised CEFR are always kept (never silently dropped). Order preserved.
    public static func atOrAbove(_ items: [ParagraphItem], minLevel: CEFR) -> [ParagraphItem] {
        items.filter { item in
            guard let level = CEFR(lenient: item.cefr) else { return true }
            return level >= minLevel
        }
    }
}
