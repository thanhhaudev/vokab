import Foundation

/// Classifies a misspelled token into the two buckets the capture gate shows
/// distinctly (SPEC: typo vs not-a-real-word), plus a safe middle bucket.
public enum SpellIssueKind: String, Sendable, Equatable {
    case typo          // misspelled, has a suggestion -> fixable
    case nonexistent   // misspelled, no suggestion, looks like gibberish -> red banner
    case unknown       // misspelled, no suggestion, but word-shaped -> mild "no suggestion" chip

    public static func classify(word: String, hasSuggestion: Bool) -> SpellIssueKind {
        if hasSuggestion { return .typo }
        return WordShape.looksLikeGibberish(word) ? .nonexistent : .unknown
    }
}
