import Foundation
import VokabKit

/// Drives a recognition review session over due cards (SPEC §11).
@MainActor
final class ReviewSessionViewModel: ObservableObject {
    @Published private(set) var cards: [ReviewCard] = []
    @Published private(set) var index = 0
    @Published var showingBack = false
    @Published private(set) var gradedCount = 0
    /// Which sense of the current word is being quizzed this showing.
    @Published private(set) var senseIndex = 0

    private let env: AppEnvironment

    init(env: AppEnvironment) { self.env = env }

    func start() {
        // No daily new-card cap; due cards first, and when nothing is due fall
        // back to all cards so the user can always study ahead.
        var due = (try? env.review.dueCards(on: Date())) ?? []
        if due.isEmpty { due = (try? env.review.allCards()) ?? [] }
        cards = due
        index = 0
        showingBack = false
        gradedCount = 0
        pickSense()
    }

    var current: ReviewCard? { index < cards.count ? cards[index] : nil }
    var isFinished: Bool { index >= cards.count }
    var remaining: Int { max(0, cards.count - index) }

    /// A card is "mature" enough for a production (writing) card once it has a
    /// week-plus interval and a couple of correct recognitions (SPEC §11).
    var currentQualifiesForProduction: Bool {
        guard let card = current else { return false }
        return ProductionGate.qualifies(
            interval: card.state.interval, reviewCount: card.state.reviewCount,
            minInterval: env.settings.productionUnlockInterval, minReps: env.settings.productionUnlockReps)
    }

    /// A card enters the cloze (fill-in-the-blank) band once it clears the cloze
    /// thresholds. `FlashcardView` checks production first, so this only applies
    /// to the band beneath production.
    var currentQualifiesForCloze: Bool {
        guard let card = current else { return false }
        return ClozeGate.qualifies(
            interval: card.state.interval, reviewCount: card.state.reviewCount,
            minInterval: env.settings.clozeUnlockInterval, minReps: env.settings.clozeUnlockReps)
    }

    /// The first error quiz for the current phrase card, or nil.
    var currentErrorQuiz: ErrorQuiz? {
        guard let card = current, card.entry.cardType == .phrase else { return nil }
        return CardDecoding.phrase(card.entry)?.commonErrors.first
    }
    /// A phrase with error data enters the error tier once matured.
    var currentQualifiesForError: Bool {
        guard let card = current, currentErrorQuiz != nil else { return false }
        return ErrorGate.qualifies(
            interval: card.state.interval, reviewCount: card.state.reviewCount,
            minInterval: env.settings.errorUnlockInterval, minReps: env.settings.errorUnlockReps)
    }

    /// The blanked example for the current card, or nil when none can be built
    /// (no example contains the headword) → caller falls back to recognition.
    var currentClozePrompt: ClozePrompt? {
        guard let card = current else { return nil }
        let entry = card.entry
        let examples: [String]
        switch entry.cardType {
        case .word:   examples = CardDecoding.word(entry)?.examples ?? []
        case .phrase: examples = CardDecoding.phrase(entry)?.examples ?? []
        default:      return nil
        }
        return ClozeBuilder.build(answer: entry.rawText, examples: examples)
    }

    /// Decoded word card for the current entry, if it is a word.
    var currentWordCard: WordCard? {
        guard let entry = current?.entry, entry.cardType == .word else { return nil }
        return CardDecoding.word(entry)
    }
    /// Senses for the current word — always ≥1 via `resolvedSenses` fallback.
    var currentSenses: [WordCard.Sense] { currentWordCard?.resolvedSenses ?? [] }
    /// The sense chosen to quiz for this showing.
    var selectedSense: WordCard.Sense? {
        let s = currentSenses
        guard !s.isEmpty else { return nil }
        return s[min(senseIndex, s.count - 1)]
    }
    /// The chosen sense's gloss in the active meaning language.
    func selectedSenseMeaning(meaningLanguage: String) -> String? {
        guard let card = currentWordCard, let sense = selectedSense else { return nil }
        return card.gloss(sense, forLanguage: meaningLanguage)
    }

    private func pickSense() {
        let n = currentSenses.count
        senseIndex = n > 1 ? Int.random(in: 0..<n) : 0
    }

    func flip() { showingBack.toggle() }

    /// Interval (days) each grade would schedule, for button labels.
    func preview() -> [ReviewGrade: Int] {
        guard let current else { return [:] }
        return SM2.intervalPreview(current.state)
    }

    func grade(_ grade: ReviewGrade) {
        guard let card = current else { return }
        let now = Date()
        let updated = SM2.schedule(card.state, grade: grade, now: now)
        try? env.review.update(updated)
        try? env.reviewLog.record(on: now)
        gradedCount += 1
        index += 1
        pickSense()
        showingBack = false
        WindowManager.notifyDataChanged()
    }
}
