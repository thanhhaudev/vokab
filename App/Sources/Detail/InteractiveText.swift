import SwiftUI
import AppKit
import VokabKit

/// Wraps any token view with a hover affordance (pointer cursor + optional
/// underline) and a tap that opens an `InlineLookupPopover` for `text`.
struct InteractiveToken<Content: View>: View {
    @EnvironmentObject private var env: AppEnvironment
    let text: String
    let hint: CardType
    let language: String
    var underlineOnHover: Bool = true
    @ViewBuilder var content: () -> Content

    @SwiftUI.State private var hovering = false
    @SwiftUI.State private var showing = false

    var body: some View {
        content()
            .overlay(alignment: .bottom) {
                if underlineOnHover && hovering {
                    Rectangle().fill(Theme.accent).frame(height: 1)
                }
            }
            .contentShape(Rectangle())
            .onHover { inside in
                hovering = inside
                if inside { NSCursor.pointingHand.push() } else { NSCursor.pop() }
            }
            .onTapGesture { showing = true }
            .popover(isPresented: $showing, arrowEdge: .bottom) {
                InlineLookupPopover(text: text, hint: hint, language: language)
                    .environmentObject(env)
            }
    }
}

/// A tokenized sentence whose single words and known multi-word phrase spans are
/// each tappable (→ lookup/capture popover). Separators render as plain text.
struct InteractiveText: View {
    let sentence: String
    let knownPhrases: [String]
    let language: String

    var body: some View {
        FlowLayout(spacing: 0, lineSpacing: 2) {
            ForEach(Array(pieces.enumerated()), id: \.offset) { _, piece in
                switch piece.kind {
                case .plain:
                    Text(piece.display).font(.system(size: 13)).foregroundStyle(Theme.textPrimary)
                case .word:
                    InteractiveToken(text: piece.lookup, hint: .word, language: language) {
                        Text(piece.display).font(.system(size: 13)).foregroundStyle(Theme.textPrimary)
                    }
                case .phrase:
                    InteractiveToken(text: piece.lookup, hint: .phrase, language: language) {
                        Text(piece.display).font(.system(size: 13)).foregroundStyle(Theme.textPrimary)
                    }
                }
            }
        }
    }

    private var pieces: [PhraseSpanMatcher.Piece] {
        PhraseSpanMatcher.pieces(sentence: sentence, phrases: knownPhrases)
    }
}

/// A `Chip` (synonym/antonym/word-family/collocation) made tappable for lookup.
/// Single-word text → word capture; multi-word → phrase capture.
struct InteractiveChip: View {
    let text: String
    let language: String
    private var hint: CardType {
        text.trimmingCharacters(in: .whitespaces).contains(" ") ? .phrase : .word
    }
    var body: some View {
        InteractiveToken(text: text, hint: hint, language: language, underlineOnHover: false) {
            Chip(text)
        }
    }
}
