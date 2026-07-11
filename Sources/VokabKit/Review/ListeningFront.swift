import Foundation

/// Decides whether a recognition card shows an audio-only *front* (word hidden,
/// its pronunciation played) instead of the text front — the "listening" card
/// (Phase 4.1). It is NOT a separate review tier: the reveal (back) and SM-2
/// grading stay the recognition path; only the front changes.
///
/// Deterministic (no randomness) so sessions and tests reproduce:
/// - `enabled` must be on;
/// - the word must be *mature* (`interval >= minInterval && reviewCount >= minReps`)
///   so we never ear-test a word the learner has barely seen spelled;
/// - among qualifying reviews it *alternates* by `reviewCount` parity, so the
///   learner keeps seeing the spelling on the interleaved (odd) reviews.
public enum ListeningFront {
    public static func shouldUseAudioFront(
        interval: Int, reviewCount: Int,
        enabled: Bool, minInterval: Int, minReps: Int
    ) -> Bool {
        guard enabled else { return false }
        guard interval >= minInterval, reviewCount >= minReps else { return false }
        return reviewCount % 2 == 0
    }
}
