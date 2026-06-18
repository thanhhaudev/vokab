import SwiftUI
import VokabKit

/// Cloze (fill-in-the-blank) card — a middle step between recognition and
/// production. Type directly into the blank, press ⏎ to reveal, self-grade (SM-2).
struct ClozeCardView: View {
    let env: AppEnvironment
    let card: ReviewCard
    let prompt: ClozePrompt
    let onGrade: (ReviewGrade) -> Void

    @State private var answer = ""
    @State private var revealed = false
    @FocusState private var focused: Bool
    @State private var translation: String?
    @State private var translating = false

    /// Soft result of the typed answer (grading is still self-directed).
    private enum Match { case exact, synonym, miss }

    private var meaning: String? {
        CardDecoding.summary(card.entry, meaningLanguage: env.settings.meaningLanguage).meaning
    }
    /// Synonyms recognised as "close" answers (word cards only; phrases have none).
    private var synonyms: [String] {
        card.entry.cardType == .word ? (CardDecoding.word(card.entry)?.synonyms ?? []) : []
    }
    private var match: Match {
        let typed = answer.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !typed.isEmpty else { return .miss }
        if typed == prompt.answer.lowercased() { return .exact }
        if synonyms.contains(where: { $0.lowercased() == typed }) { return .synonym }
        return .miss
    }
    private var completedSentence: String {
        prompt.sentence.replacingOccurrences(of: ClozeBuilder.blank, with: prompt.answer)
    }

    private var matchColor: Color {
        switch match {
        case .exact:   return Theme.diffIns          // green
        case .synonym: return Theme.dueColor(.new)   // teal
        case .miss:    return Theme.dueColor(.today)  // amber
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 6) {
                    Text(L.t("Cloze", "Điền từ")).font(.system(size: 11, weight: .medium))
                        .padding(.horizontal, 8).padding(.vertical, 2)
                        .background(Theme.accentBg, in: Capsule()).foregroundStyle(Theme.accentText)
                    if let cefr = card.entry.cefr { Pill.cefr(cefr) }
                }
                if let meaning {
                    Text(meaning).font(.system(size: 14)).foregroundStyle(Theme.textSecondary)
                }
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
                } else { hintRow }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(16)
            Spacer(minLength: 0)
            if revealed { gradeButtons }
        }
        .background(Theme.bgPrimary)
        .onAppear { focused = true }
        .task(id: revealed) { if revealed { await loadTranslation() } }
    }

    @MainActor private func loadTranslation() async {
        guard env.settings.meaningLanguage != "en" else { return }
        translating = true
        translation = try? await env.translation.translate(completedSentence, to: env.settings.meaningLanguage)
        translating = false
    }

    // MARK: Sentence with an inline underlined blank

    /// The example laid out word-by-word so the blank can be an inline field on a
    /// thick primary underline — typed in place, wrapping like normal text.
    private var sentenceView: some View {
        let parts = prompt.sentence.components(separatedBy: ClozeBuilder.blank)
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

    /// The blank: an inline text field (before reveal) or the answer (after), both
    /// sitting on a thick primary-colored underline.
    @ViewBuilder private var blankView: some View {
        if revealed {
            Text(prompt.answer)
                .font(.system(size: 17, weight: .medium)).foregroundStyle(matchColor)
                .padding(.horizontal, 4)
                .overlay(alignment: .bottom) { underline(matchColor) }
        } else {
            TextField("", text: $answer)
                .textFieldStyle(.plain)
                .font(.system(size: 17))
                .multilineTextAlignment(.center)
                .focused($focused)
                .frame(width: blankWidth)
                .padding(.horizontal, 4)
                .overlay(alignment: .bottom) { underline(Theme.accent) }
                .onSubmit { revealed = true }
        }
    }

    private func underline(_ color: Color) -> some View {
        Rectangle().fill(color).frame(height: 2.5)
    }

    /// Width hints at the answer length without exposing it precisely.
    private var blankWidth: CGFloat {
        min(max(CGFloat(prompt.answer.count) * 12 + 24, 80), 220)
    }

    private var hintRow: some View {
        HStack(spacing: 6) {
            Text("↵").font(Theme.mono(11)).foregroundStyle(Theme.accentText)
                .padding(.horizontal, 6).padding(.vertical, 1)
                .background(Theme.accentBg, in: RoundedRectangle(cornerRadius: 5))
            Text(L.t("to check", "để kiểm tra")).font(.system(size: 12)).foregroundStyle(Theme.textTertiary)
        }
    }

    private var statusView: some View {
        HStack(spacing: 6) {
            Image(systemName: statusIcon).foregroundStyle(matchColor)
            Text(statusText).font(.system(size: 13)).foregroundStyle(Theme.textSecondary)
        }
    }

    private var statusIcon: String {
        switch match {
        case .exact:   return "checkmark.circle.fill"
        case .synonym: return "checkmark.circle"
        case .miss:    return "pencil.circle"
        }
    }
    private var statusText: String {
        switch match {
        case .exact:   return L.t("Correct", "Chính xác")
        case .synonym: return L.t("≈ Synonym · answer: \(prompt.answer)", "≈ Đồng nghĩa · đáp án: \(prompt.answer)")
        case .miss:    return L.t("Answer: \(prompt.answer)", "Đáp án: \(prompt.answer)")
        }
    }

    // MARK: Grade buttons

    private var gradeButtons: some View {
        GradeButtons(preview: SM2.intervalPreview(card.state), onGrade: onGrade)
    }
}
