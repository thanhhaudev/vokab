import Foundation

/// Decides when a phrase has matured enough for the error-correction tier.
/// Checked before production in `FlashcardView`, so an error-prone phrase drills
/// its mistakes instead of free-writing once it clears these thresholds.
public enum ErrorGate {
    public static func qualifies(interval: Int, reviewCount: Int, minInterval: Int, minReps: Int) -> Bool {
        interval >= minInterval && reviewCount >= minReps
    }
}
