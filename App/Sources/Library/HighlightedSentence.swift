import SwiftUI
import VokabKit

/// A sentence with `target` highlighted, matching the extraction "Source" block
/// (`Theme.highlightBg` / `Theme.highlightText`) so the word a learner saw
/// highlighted during capture stays visually consistent in review and detail.
struct HighlightedSentence: View {
    let sentence: String
    let target: String

    var body: some View {
        Text(attributed)
    }

    private var attributed: AttributedString {
        var attr = AttributedString()
        for seg in ParagraphHighlighter.segments(source: sentence, candidates: [target]) {
            var run = AttributedString(seg.text)
            if seg.isHighlight {
                run.backgroundColor = Theme.highlightBg
                run.foregroundColor = Theme.highlightText
            } else {
                run.foregroundColor = Theme.textPrimary
            }
            attr.append(run)
        }
        return attr
    }
}
