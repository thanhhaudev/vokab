import Foundation

/// Normalization used for cache keys and dedup lookups (SPEC §9, §11).
public enum TextKey {
    /// Lowercased, whitespace-trimmed, internal whitespace collapsed.
    public static func normalize(_ text: String) -> String {
        text
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
            .components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
    }

    /// Cache/dedup key combining normalized text and language.
    public static func cacheKey(text: String, language: String) -> String {
        "\(normalize(text))::\(language.lowercased())"
    }

    /// Cache key for a paragraph extraction at a given minimum CEFR level.
    /// Distinct min levels must NOT share a cache entry (a higher level yields
    /// fewer words), so the level is folded into the key.
    public static func cacheKey(text: String, language: String, minLevel: CEFR) -> String {
        "\(cacheKey(text: text, language: language))::min=\(minLevel.rawValue)"
    }

    /// Day string ("yyyy-MM-dd") for quota bucketing, in the current calendar.
    public static func dayString(_ date: Date, calendar: Calendar = .current) -> String {
        let c = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", c.year ?? 0, c.month ?? 0, c.day ?? 0)
    }
}
