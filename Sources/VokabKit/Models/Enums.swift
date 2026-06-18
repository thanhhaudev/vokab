import Foundation

/// What kind of entry a captured item is.
public enum CardType: String, Codable, Sendable, CaseIterable {
    case word
    case phrase
    case paragraphItem = "paragraph_item"
}

/// CEFR proficiency level. Decoded leniently from whatever casing agy returns.
public enum CEFR: String, Codable, Sendable, CaseIterable, Comparable {
    case a1, a2, b1, b2, c1, c2

    /// Lenient parse: accepts "C1", "c1", " B2 ", etc. Returns nil if unknown.
    public init?(lenient raw: String?) {
        guard let raw else { return nil }
        let normalized = raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard let value = CEFR(rawValue: normalized) else { return nil }
        self = value
    }

    private var order: Int { Self.allCases.firstIndex(of: self)! }

    public static func < (lhs: CEFR, rhs: CEFR) -> Bool { lhs.order < rhs.order }
}

/// SM-2 review grades, ordered easiest-recall ascending.
public enum ReviewGrade: Int, Codable, Sendable, CaseIterable {
    case again = 0
    case hard = 1
    case good = 2
    case easy = 3
}

/// Lifecycle state for async capture: entry is inserted immediately as `analyzing`,
/// then flipped to `ready` (or `failed`) by the background worker.
public enum AnalysisState: String, Codable, Sendable, CaseIterable {
    case analyzing, ready, failed
}

/// Whether a card is reviewed by recognition (recall meaning) or production
/// (write a sentence, AI-graded).
public enum CardMode: String, Codable, Sendable {
    case recognition
    case production
}
