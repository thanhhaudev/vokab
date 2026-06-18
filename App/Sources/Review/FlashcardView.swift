import SwiftUI
import VokabKit

/// Recognition flashcard (SPEC §12 surface #5).
struct FlashcardView: View {
    @EnvironmentObject var env: AppEnvironment
    @StateObject private var model: ReviewSessionViewModel

    init(env: AppEnvironment) {
        _model = StateObject(wrappedValue: ReviewSessionViewModel(env: env))
    }

    var body: some View {
        VStack(spacing: 0) {
            progressBar
            if model.isFinished {
                Spacer(); finished; Spacer()
            } else if let card = model.current {
                if model.currentQualifiesForError, let quiz = model.currentErrorQuiz {
                    ErrorCardView(env: env, card: card, quiz: quiz) { grade in model.grade(grade) }
                        .id(card.entry.id)
                } else if model.currentQualifiesForProduction {
                    ProductionCardView(env: env, card: card) { grade in model.grade(grade) }
                        .id(card.entry.id)
                } else if model.currentQualifiesForCloze, let prompt = model.currentClozePrompt {
                    ClozeCardView(env: env, card: card, prompt: prompt) { grade in model.grade(grade) }
                        .id(card.entry.id)
                } else {
                    recognition(card)
                }
            }
        }
        .background(Theme.bgPrimary)
        .onAppear { model.start() }
    }

    private var progressBar: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Rectangle().fill(Theme.borderTertiary)
                Rectangle().fill(Theme.accent)
                    .frame(width: geo.size.width * progress)
            }
        }
        .frame(height: 3)
    }

    private var progress: CGFloat {
        guard !model.cards.isEmpty else { return 0 }
        return CGFloat(model.index) / CGFloat(model.cards.count)
    }

    // MARK: Recognition

    @ViewBuilder private func recognition(_ card: ReviewCard) -> some View {
        let summary = CardDecoding.summary(card.entry, meaningLanguage: env.settings.meaningLanguage)
        VStack(spacing: 0) {
            // Front
            VStack(spacing: 4) {
                HStack(spacing: 4) {
                    if let cefr = summary.cefr { Pill.cefr(cefr) }
                    if let pos = summary.pos { Pill(pos, style: .type) }
                }
                Text(card.entry.rawText)
                    .font(.system(size: 30, weight: .medium)).foregroundStyle(Theme.textPrimary)
                    .padding(.top, 10)
                if let ipa = wordIPA(card.entry) {
                    Text(ipa).font(Theme.mono(14)).foregroundStyle(Theme.textSecondary)
                }
                PronounceButton(text: card.entry.rawText,
                                accent: Accent(settingsValue: env.settings.pronunciationAccent))
                    .padding(.top, 6)
            }
            .frame(maxWidth: .infinity)
            .padding(.top, 34).padding(.bottom, 24).padding(.horizontal, 24)

            if model.showingBack {
                back(card, summary: summary)
            }

            Spacer(minLength: 0)

            if model.showingBack {
                gradeButtons
            } else {
                Button(L.t("Show answer", "Hiện đáp án")) { model.flip() }
                    .keyboardShortcut(.space, modifiers: [])
                    .buttonStyle(.vPrimary)
                    .padding(.bottom, 20)
            }
        }
        .onChange(of: model.showingBack) { _, revealed in
            guard revealed, env.settings.autoPlayPronunciation else { return }
            Speaker.shared.speak(card.entry.rawText,
                                 accent: Accent(settingsValue: env.settings.pronunciationAccent))
        }
    }

    private func back(_ card: ReviewCard, summary: (pos: String?, meaning: String?, cefr: String?)) -> some View {
        VStack(spacing: 6) {
            if let meaning = summary.meaning {
                Text(meaning).font(.system(size: 16, weight: .medium)).foregroundStyle(Theme.textPrimary)
            }
            if let en = wordMeaningEn(card.entry) {
                Text(en).font(.system(size: 13)).foregroundStyle(Theme.textSecondary)
                    .multilineTextAlignment(.center).lineSpacing(3).frame(maxWidth: 420)
            }
            if let sentence = card.entry.captureSentence {
                VStack(alignment: .leading, spacing: 4) {
                    SecLabel("Seen in")
                    HighlightedSentence(sentence: sentence, target: card.entry.rawText)
                        .font(.system(size: 13)).lineSpacing(3)
                        .frame(maxWidth: 420, alignment: .leading).padding(.leading, 10)
                        .overlay(alignment: .leading) { Rectangle().fill(Theme.accent).frame(width: 2) }
                }
                .frame(maxWidth: 420, alignment: .leading).padding(.top, 8)
            } else if let example = wordExample(card.entry) {
                Text(example).font(.system(size: 13)).foregroundStyle(Theme.textPrimary)
                    .frame(maxWidth: 420, alignment: .leading).padding(.leading, 10).padding(.top, 8)
                    .overlay(alignment: .leading) { Rectangle().fill(Theme.borderSecondary).frame(width: 2) }
            }
            if let app = card.entry.sourceApp {
                Label("Captured from \(app)", systemImage: "bookmark")
                    .font(.system(size: 11)).foregroundStyle(Theme.textTertiary)
                    .padding(.horizontal, 10).padding(.vertical, 3)
                    .background(Theme.bgPrimary, in: Capsule())
                    .overlay(Capsule().strokeBorder(Theme.borderTertiary, lineWidth: Theme.hairline))
                    .padding(.top, 14)
            }
            CategoryPill(current: card.entry.category) { picked in
                if let id = card.entry.id {
                    try? env.entries.setCategory(id: id, category: picked)
                    WindowManager.notifyDataChanged()
                }
            }
            .padding(.top, 6)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 18).padding(.horizontal, 24)
        .background(Theme.bgSecondary)
        .overlay(alignment: .top) { Hairline() }
    }

    // MARK: Grade buttons

    private var gradeButtons: some View {
        GradeButtons(preview: model.preview(), onGrade: { model.grade($0) })
    }

    private var finished: some View {
        VStack(spacing: 16) {
            ContentUnavailableView(L.t("All done", "Hoàn thành"), systemImage: "checkmark.circle.fill",
                                   description: Text(L.t("Reviewed \(model.gradedCount) cards.",
                                                         "Đã ôn \(model.gradedCount) thẻ.")))
            Button(L.t("Done", "Xong")) { WindowManager.shared.closeReview() }
                .buttonStyle(.vPrimary)
        }
    }

    // MARK: Field extraction

    private func wordIPA(_ entry: Entry) -> String? { CardDecoding.word(entry)?.ipa }
    private func wordMeaningEn(_ entry: Entry) -> String? {
        if entry.cardType == .word { return CardDecoding.word(entry)?.meaningEn }
        if entry.cardType == .phrase { return CardDecoding.phrase(entry)?.meaningEn }
        return nil
    }
    private func wordExample(_ entry: Entry) -> String? {
        if entry.cardType == .word { return CardDecoding.word(entry)?.examples.first }
        if entry.cardType == .phrase { return CardDecoding.phrase(entry)?.examples.first }
        return nil
    }
}

extension ReviewGrade {
    var kind: ReviewGradeKind {
        switch self {
        case .again: return .again
        case .hard: return .hard
        case .good: return .good
        case .easy: return .easy
        }
    }
}
