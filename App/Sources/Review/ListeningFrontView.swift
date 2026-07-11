import SwiftUI
import VokabKit

/// Audio-only front for a recognition card (P4.1). Hides the word, auto-plays its
/// pronunciation, and offers replay + "in a sentence". The reveal (back) and SM-2
/// grading remain the recognition path — this view is only the top block; the
/// shared "Show answer" button below it (in `FlashcardView`) does the flip.
struct ListeningFrontView: View {
    let env: AppEnvironment
    let card: ReviewCard

    private var accent: Accent { Accent(settingsValue: env.settings.pronunciationAccent) }

    /// A sentence to play on demand: the original captured sentence if we have
    /// one, else the first example. nil → hide the "in a sentence" button.
    private var contextSentence: String? {
        if let s = card.entry.captureSentence, !s.isEmpty { return s }
        switch card.entry.cardType {
        case .word:   return CardDecoding.word(card.entry)?.examples.first
        case .phrase: return CardDecoding.phrase(card.entry)?.examples.first
        default:      return nil
        }
    }

    var body: some View {
        VStack(spacing: 12) {
            HStack(spacing: 4) {
                Text(L.t("Listening", "Nghe")).font(.system(size: 11, weight: .medium))
                    .padding(.horizontal, 8).padding(.vertical, 2)
                    .background(Theme.accentBg, in: Capsule()).foregroundStyle(Theme.accentText)
                if let cefr = card.entry.cefr { Pill.cefr(cefr) }
            }
            Image(systemName: "ear")
                .font(.system(size: 40, weight: .light)).foregroundStyle(Theme.accent)
                .padding(.vertical, 4)
                .accessibilityLabel(L.t("Listen", "Nghe"))
            HStack(spacing: 10) {
                PronounceButton(text: card.entry.rawText, accent: accent)
                if let sentence = contextSentence {
                    Button {
                        Speaker.shared.speak(sentence, accent: accent)
                    } label: {
                        Label(L.t("In a sentence", "Trong câu"), systemImage: "text.quote")
                            .font(.system(size: 12))
                    }
                    .buttonStyle(.plain).foregroundStyle(Theme.accentText)
                    .padding(.horizontal, 10).padding(.vertical, 4)
                    .background(Theme.accentBg, in: Capsule())
                }
            }
            Text(L.t("What does it mean?", "Từ này nghĩa là gì?"))
                .font(.system(size: 13)).foregroundStyle(Theme.textTertiary)
        }
        // Re-fires per card (id-keyed), so advancing to the next card auto-plays it.
        .task(id: card.entry.id) {
            Speaker.shared.speak(card.entry.rawText, accent: accent)
        }
    }
}
