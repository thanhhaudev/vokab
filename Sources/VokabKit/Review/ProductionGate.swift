import Foundation

/// Decides when a card is mature enough for a production (writing) card (SPEC §11).
public enum ProductionGate {
    public static func qualifies(interval: Int, reviewCount: Int, minInterval: Int, minReps: Int) -> Bool {
        interval >= minInterval && reviewCount >= minReps
    }
}

/// Caps how many new cards (never reviewed) enter a session, keeping all reviews.
public enum NewCardLimit {
    /// Returns `cards` with at most `limit` items for which `isNew` is true,
    /// preserving order and keeping every non-new card.
    public static func apply<T>(_ cards: [T], isNew: (T) -> Bool, limit: Int) -> [T] {
        var newSeen = 0
        return cards.filter { card in
            if isNew(card) {
                newSeen += 1
                return newSeen <= limit
            }
            return true
        }
    }
}
