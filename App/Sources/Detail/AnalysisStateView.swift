import SwiftUI
import VokabKit

/// A single placeholder line for the analysis skeleton.
struct SkeletonLine {
    let text: String
    let size: CGFloat
    let weight: Font.Weight

    init(_ text: String, size: CGFloat, weight: Font.Weight = .regular) {
        self.text = text
        self.size = size
        self.weight = weight
    }
}

/// Shimmer placeholder shown while an entry is being analyzed in the background.
/// Used by WordDetailView and PhraseDetailView; each passes its own title font size,
/// vertical padding, and placeholder lines to preserve the existing per-type visuals.
struct AnalysisSkeletonView: View {
    let rawText: String
    var titleSize: CGFloat
    var verticalPadding: CGFloat
    let placeholderLines: [SkeletonLine]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(rawText)
                .font(.system(size: titleSize, weight: .medium))
                .foregroundStyle(Theme.textPrimary)
                .padding(.horizontal, 16)
                .padding(.top, verticalPadding)
            VStack(alignment: .leading, spacing: 8) {
                ForEach(Array(placeholderLines.enumerated()), id: \.offset) { _, line in
                    Text(line.text).font(.system(size: line.size, weight: line.weight))
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 16)
            .padding(.bottom, verticalPadding)
            .skeleton()
        }
    }
}

/// "Phân tích thất bại" banner + Retry button, shown when an entry's analysis failed.
/// Used by WordDetailView and PhraseDetailView. The Library row has its own compact
/// inline rendering and only reuses the retryAnalysis helper.
struct AnalysisFailedView: View {
    let rawText: String
    var titleSize: CGFloat
    var verticalPadding: CGFloat
    let onRetry: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(rawText)
                .font(.system(size: titleSize, weight: .medium))
                .foregroundStyle(Theme.textPrimary)
                .padding(.horizontal, 16)
                .padding(.top, verticalPadding)
            HStack(spacing: 10) {
                Image(systemName: "exclamationmark.circle")
                    .foregroundStyle(Theme.textTertiary)
                Text(L.t("Analysis failed", "Phân tích thất bại"))
                    .font(.system(size: 13)).foregroundStyle(Theme.textTertiary)
                Spacer()
                Button(L.t("Retry", "Thử lại")) { onRetry() }
                    .buttonStyle(.plain)
                    .font(.system(size: 13)).foregroundStyle(Theme.accent)
            }
            .padding(.horizontal, 16)
            .padding(.bottom, verticalPadding)
        }
    }
}
