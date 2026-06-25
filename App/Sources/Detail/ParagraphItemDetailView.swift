import SwiftUI
import VokabKit

/// Detail for a single vocabulary item extracted from a paragraph.
struct ParagraphItemDetailView: View {
    let entry: Entry
    private var item: ParagraphItem? { CardDecoding.paragraphItem(entry) }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                HStack(alignment: .lastTextBaseline, spacing: 12) {
                    Text(entry.rawText).font(.system(size: 26, weight: .medium)).foregroundStyle(Theme.textPrimary)
                    if let pos = item?.pos { Pill(pos, style: .type) }
                    if let cefr = item?.cefr { Pill.cefr(cefr) }
                }
                if let m = item?.meaning {
                    Text(m).font(.system(size: 15, weight: .medium)).foregroundStyle(Theme.textPrimary)
                }
                if let reason = item?.reasonToLearn {
                    VStack(alignment: .leading, spacing: 6) {
                        SecLabel("Why learn it")
                        Text(reason).font(.system(size: 13)).foregroundStyle(Theme.textSecondary).lineSpacing(3)
                    }
                    .padding(12)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Theme.bgSecondary, in: RoundedRectangle(cornerRadius: Theme.radiusMd))
                }
                Spacer(minLength: 0)
                if let app = entry.sourceApp {
                    Text("Captured from \(app)").font(.system(size: 12)).foregroundStyle(Theme.textTertiary)
                }
            }
            .padding(20)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(Theme.bgPrimary)
    }
}
