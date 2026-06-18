import SwiftUI
import VokabKit

/// SM-2 self-grade button row (Again / Hard / Good / Easy).
/// Shared by FlashcardView, ClozeCardView, and ErrorCardView.
/// ProductionCardView uses a different button shape (suggested-grade highlight)
/// and is left with its own implementation.
struct GradeButtons: View {
    /// Interval preview in days, keyed by grade (nil = "<1 min" bucket).
    let preview: [ReviewGrade: Int]
    let onGrade: (ReviewGrade) -> Void

    var body: some View {
        HStack(spacing: 8) {
            srButton("Again", .again, preview[.again])
            srButton("Hard",  .hard,  preview[.hard])
            srButton("Good",  .good,  preview[.good])
            srButton("Easy",  .easy,  preview[.easy])
        }
        .padding(.horizontal, 16).padding(.vertical, 14)
        .overlay(alignment: .top) { Hairline() }
    }

    private func srButton(_ label: String, _ grade: ReviewGrade, _ days: Int?) -> some View {
        Button { onGrade(grade) } label: {
            VStack(spacing: 2) {
                Text(label)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(Theme.gradeColor(grade.kind))
                Text(intervalLabel(days))
                    .font(.system(size: 11))
                    .foregroundStyle(Theme.textTertiary)
            }
            .frame(maxWidth: .infinity).padding(.vertical, 9)
            .background(Theme.bgPrimary, in: RoundedRectangle(cornerRadius: Theme.radiusMd))
            .overlay(RoundedRectangle(cornerRadius: Theme.radiusMd)
                .strokeBorder(Theme.borderSecondary, lineWidth: Theme.hairline))
        }
        .buttonStyle(.plain)
    }

    private func intervalLabel(_ days: Int?) -> String {
        guard let days else { return "" }
        if days <= 0 { return "<1 min" }
        if days == 1 { return "1 day" }
        return "\(days) days"
    }
}
