import Foundation

/// Decides when a card has matured enough for a cloze (fill-in-the-blank) card —
/// a middle stage between recognition and production. Thresholds sit below
/// production's so cloze occupies the band beneath it; `FlashcardView` checks
/// production first, so any overlap from user-set thresholds is harmless.
public enum ClozeGate {
    public static func qualifies(interval: Int, reviewCount: Int, minInterval: Int, minReps: Int) -> Bool {
        interval >= minInterval && reviewCount >= minReps
    }
}
