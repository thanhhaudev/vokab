import SwiftUI
import VokabKit

/// Error-correction card — tap the correct option to fix the blank, reveal,
/// self-grade (SM-2). Phrase-only; one quiz per card.
struct ErrorCardView: View {
    @Environment(\.displayScale) private var displayScale
    let env: AppEnvironment
    let card: ReviewCard
    let quiz: ErrorQuiz
    let onGrade: (ReviewGrade) -> Void

    @State private var picked: String?
    @State private var translation: String?
    @State private var translating = false

    private var revealed: Bool { picked != nil }
    private var completedSentence: String {
        quiz.sentence.replacingOccurrences(of: ClozeBuilder.blank, with: quiz.answer)
    }
    private var isCorrect: Bool {
        picked?.trimmingCharacters(in: .whitespaces).lowercased() == quiz.answer.lowercased()
    }
    private var resultColor: Color { isCorrect ? Theme.diffIns : Theme.dueColor(.today) }
    private var meaning: String? {
        CardDecoding.summary(card.entry, meaningLanguage: env.settings.meaningLanguage).meaning
    }

    var body: some View {
        VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 6) {
                    Text(L.t("Fix the error", "Sửa lỗi")).font(.system(size: 11, weight: .medium))
                        .padding(.horizontal, 8).padding(.vertical, 2)
                        .background(Theme.accentBg, in: Capsule()).foregroundStyle(Theme.accentText)
                    if let cefr = card.entry.cefr { Pill.cefr(cefr) }
                }
                if let meaning { Text(meaning).font(.system(size: 14)).foregroundStyle(Theme.textSecondary) }
                sentenceView
                if revealed {
                    statusView
                    if translating {
                        Text(L.t("Translating this sentence for you", "Đang dịch câu này sang tiếng Việt"))
                            .font(.system(size: 13)).foregroundStyle(Theme.textSecondary)
                            .skeleton()
                    } else if let translation {
                        Text(translation).font(.system(size: 13)).foregroundStyle(Theme.textSecondary).italic()
                    }
                } else { optionTiles }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(16)
            Spacer(minLength: 0)
            if revealed { gradeButtons }
        }
        .background(Theme.bgPrimary)
        .task(id: picked) { if picked != nil { await loadTranslation() } }
    }

    @MainActor private func loadTranslation() async {
        guard env.settings.meaningLanguage != "en" else { return }
        translating = true
        translation = try? await env.translation.translate(completedSentence, to: env.settings.meaningLanguage)
        translating = false
    }

    private var sentenceView: some View {
        let parts = quiz.sentence.components(separatedBy: ClozeBuilder.blank)
        let before = words(parts.first ?? "")
        let after = words(parts.dropFirst().joined(separator: ClozeBuilder.blank))
        return FlowLayout(spacing: 5) {
            ForEach(Array(before.enumerated()), id: \.offset) { _, w in wordText(w) }
            blankView
            ForEach(Array(after.enumerated()), id: \.offset) { _, w in wordText(w) }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
    private func words(_ s: String) -> [String] { s.split(separator: " ").map(String.init) }
    private func wordText(_ w: String) -> some View {
        Text(w).font(.system(size: 17)).foregroundStyle(Theme.textPrimary)
    }
    @ViewBuilder private var blankView: some View {
        if let picked {
            Text(picked).font(.system(size: 17, weight: .medium)).foregroundStyle(resultColor)
                .padding(.horizontal, 4)
                .overlay(alignment: .bottom) { Rectangle().fill(resultColor).frame(height: 2.5) }
        } else {
            RoundedRectangle(cornerRadius: 6).strokeBorder(Theme.accent, lineWidth: 1.5)
                .frame(width: 96, height: 26)
        }
    }

    private var optionTiles: some View {
        FlowLayout(spacing: 8) {
            ForEach(quiz.options, id: \.self) { opt in
                Button { picked = opt } label: {
                    Text(opt).font(.system(size: 15)).foregroundStyle(Theme.textPrimary)
                        .padding(.horizontal, 12).padding(.vertical, 6)
                        .background(Theme.bgSecondary, in: RoundedRectangle(cornerRadius: 8))
                        .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(Theme.borderSecondary, lineWidth: Theme.hairline(displayScale)))
                }
                .buttonStyle(.plain)
            }
        }
    }

    private var statusView: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                Image(systemName: isCorrect ? "checkmark.circle.fill" : "xmark.circle").foregroundStyle(resultColor)
                Text(isCorrect ? L.t("Correct", "Chính xác")
                               : L.t("Answer: \(quiz.answer)", "Đáp án: \(quiz.answer)"))
                    .font(.system(size: 13)).foregroundStyle(Theme.textSecondary)
            }
            if let note = quiz.noteVi, !note.isEmpty {
                Text(note).font(.system(size: 12)).foregroundStyle(Theme.textTertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var gradeButtons: some View {
        GradeButtons(preview: SM2.intervalPreview(card.state), onGrade: onGrade)
    }
}
