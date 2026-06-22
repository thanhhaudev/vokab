import SwiftUI
import VokabKit

/// Production / writing card (SPEC §12 surface #6, §11).
struct ProductionCardView: View {
    @Environment(\.displayScale) private var displayScale
    let env: AppEnvironment
    let card: ReviewCard
    let onGrade: (ReviewGrade) -> Void

    @State private var sentence = ""
    @State private var feedback: ProductionFeedback?
    @State private var phase: Phase = .writing
    @State private var submitting = false
    @State private var errorMessage: String?

    enum Phase { case writing, correct, wrong }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            prompt
            answerField
            switch phase {
            case .writing:  writingControls
            case .correct:  correctFeedback
            case .wrong:    wrongFeedback
            }
            if let errorMessage {
                Text(errorMessage).font(.system(size: 12)).foregroundStyle(Theme.textDanger)
            }
            Spacer(minLength: 0)
        }
        .padding(16)
        .background(Theme.bgPrimary)
    }

    private var prompt: some View {
        HStack(alignment: .lastTextBaseline, spacing: 8) {
            Text(L.t("Write a sentence using", "Viết một câu dùng")).font(.system(size: 13)).foregroundStyle(Theme.textTertiary)
            Text(card.entry.rawText).font(.system(size: 16, weight: .medium)).foregroundStyle(Theme.textPrimary)
            if let cefr = card.entry.cefr { Pill.cefr(cefr) }
            if let pos = CardDecoding.summary(card.entry, meaningLanguage: env.settings.meaningLanguage).pos {
                Pill(pos, style: .type)
            }
        }
    }

    private var answerField: some View {
        Group {
            if phase == .writing {
                TextEditor(text: $sentence)
                    .font(.system(size: 14)).scrollContentBackground(.hidden)
                    .frame(minHeight: 70).padding(8)
                    .background(Theme.bgPrimary, in: RoundedRectangle(cornerRadius: Theme.radiusMd))
                    .overlay(RoundedRectangle(cornerRadius: Theme.radiusMd).strokeBorder(Theme.borderSecondary, lineWidth: Theme.hairline(displayScale)))
            } else {
                originalText
                    .font(.system(size: 14)).lineSpacing(3)
                    .frame(maxWidth: .infinity, alignment: .leading).padding(10)
                    .background(Theme.bgPrimary, in: RoundedRectangle(cornerRadius: Theme.radiusMd))
                    .overlay(RoundedRectangle(cornerRadius: Theme.radiusMd).strokeBorder(Theme.borderSecondary, lineWidth: Theme.hairline(displayScale)))
            }
        }
    }

    private var writingControls: some View {
        HStack {
            Button(L.t("Check", "Kiểm tra")) { submit() }
                .buttonStyle(.vPrimary)
                .disabled(sentence.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || submitting)
            if submitting { ProgressView().controlSize(.small) }
            Spacer()
            Button(L.t("Skip", "Bỏ qua")) { onGrade(.hard) }.buttonStyle(.vSecondary)
        }
    }

    // MARK: Correct

    private var correctFeedback: some View {
        VStack(alignment: .leading, spacing: 10) {
            feedbackBox(bg: Theme.successBg, border: Theme.sugBorder) {
                Label(L.t("Correct & very natural", "Chính xác & rất tự nhiên"), systemImage: "checkmark")
                    .font(.system(size: 13, weight: .medium)).foregroundStyle(Theme.successFg)
                if let explanation = feedback?.explanationVi, !explanation.isEmpty {
                    Text(explanation).font(.system(size: 13)).foregroundStyle(Theme.dyn(light: 0x3B6D11, dark: 0x9BC47A)).lineSpacing(2)
                }
            }
            HStack(spacing: 7) {
                Text(L.t("agy graded:", "agy chấm:")).font(.system(size: 11)).foregroundStyle(Theme.textTertiary)
                ForEach(ReviewGrade.allCases, id: \.self) { grade in sugButton(grade) }
            }
        }
    }

    // MARK: Wrong

    private var wrongFeedback: some View {
        VStack(alignment: .leading, spacing: 10) {
            feedbackBox(bg: Theme.highlightBg, border: Theme.dyn(light: 0xEF9F27, dark: 0xF5B84A)) {
                Label(L.t("Almost — needs a fix", "Gần đúng — cần chỉnh"), systemImage: "lightbulb")
                    .font(.system(size: 13, weight: .medium)).foregroundStyle(Theme.highlightText)
                correctedText.font(.system(size: 14)).lineSpacing(3).padding(.top, 2)
                if let explanation = feedback?.explanationVi, !explanation.isEmpty {
                    Text(explanation).font(.system(size: 13)).foregroundStyle(Theme.warnFg).lineSpacing(2)
                }
            }
            HStack {
                Text(L.t("This card will return sooner", "Thẻ này sẽ quay lại sớm hơn"))
                    .font(.system(size: 11)).foregroundStyle(Theme.textTertiary)
                Spacer()
                Button { reset() } label: { Label(L.t("Retry", "Thử lại"), systemImage: "arrow.clockwise") }
                    .buttonStyle(.vSecondary)
                Button(L.t("Got it, next →", "Đã hiểu, tiếp →")) { onGrade(.again) }.buttonStyle(.vPrimary)
            }
        }
    }

    // MARK: Feedback box chrome

    private func feedbackBox<C: View>(bg: Color, border: Color, @ViewBuilder content: () -> C) -> some View {
        VStack(alignment: .leading, spacing: 7) { content() }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 13).padding(.vertical, 11)
            .background(bg)
            .overlay(alignment: .leading) { Rectangle().fill(border).frame(width: 3) }
            .clipShape(RoundedRectangle(cornerRadius: Theme.radiusMd))
    }

    private func sugButton(_ grade: ReviewGrade) -> some View {
        let suggested = feedback?.suggestedGrade == grade
        return Button { onGrade(grade) } label: {
            Text(grade.displayName + (suggested ? " ✓" : ""))
                .font(.system(size: 13, weight: suggested ? .medium : .regular))
                .foregroundStyle(Theme.gradeColor(grade.kind))
                .frame(maxWidth: .infinity).padding(.vertical, 7)
                .background(suggested ? Theme.sugBg : Theme.bgPrimary, in: RoundedRectangle(cornerRadius: Theme.radiusMd))
                .overlay(RoundedRectangle(cornerRadius: Theme.radiusMd)
                    .strokeBorder(suggested ? Theme.sugBorder : Theme.borderSecondary, lineWidth: suggested ? 1.5 : Theme.hairline(displayScale)))
        }
        .buttonStyle(.plain)
    }

    // MARK: Diff rendering

    /// What the user wrote: keep + del tokens (del struck, red).
    private var originalText: Text {
        guard let diff = feedback?.diff, !diff.isEmpty else { return Text(sentence) }
        return diff.filter { $0.type != "ins" }.reduce(Text("")) { acc, token in
            var piece = Text(token.text)
            if token.type == "del" { piece = piece.foregroundColor(Theme.diffDel).strikethrough() }
            return acc + piece
        }
    }

    /// Corrected sentence: keep + ins tokens (ins green).
    private var correctedText: Text {
        guard let diff = feedback?.diff, !diff.isEmpty else {
            return Text(feedback?.correctedSentence ?? "")
        }
        return diff.filter { $0.type != "del" }.reduce(Text("")) { acc, token in
            var piece = Text(token.text)
            if token.type == "ins" { piece = piece.foregroundColor(Theme.diffIns).bold() }
            return acc + piece
        }
    }

    private func submit() {
        let text = sentence.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        submitting = true; errorMessage = nil
        Task {
            do {
                let fb = try await env.agy.judgeProduction(word: card.entry.rawText, sentence: text)
                feedback = fb
                phase = (fb.verdict?.lowercased() == "correct") ? .correct : .wrong
            } catch {
                errorMessage = "agy couldn't judge this sentence. Try again."
            }
            submitting = false
        }
    }

    private func reset() { feedback = nil; phase = .writing }
}
