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
            ForEach(Array(renderTokens.enumerated()), id: \.offset) { _, tok in
                switch tok.kind {
                case .plain:
                    Text(tok.display).font(.system(size: 13)).foregroundStyle(Theme.textPrimary)
                case .word:
                    InteractiveToken(text: tok.lookup, hint: .word, language: language) {
                        Text(tok.display).font(.system(size: 13)).foregroundStyle(Theme.textPrimary)
                    }
                case .phrase:
                    InteractiveToken(text: tok.lookup, hint: .phrase, language: language) {
                        Text(tok.display).font(.system(size: 13)).foregroundStyle(Theme.textPrimary)
                    }
                }
            }
        }
    }

    private enum Kind { case plain, word, phrase }
    private struct Token { let display: String; let lookup: String; let kind: Kind }

    /// Builds render tokens from the sentence's atoms + matched phrase spans.
    /// Word atoms become `.word`; consecutive word atoms inside a phrase span are
    /// merged (with their interleaving separators) into one `.phrase`; everything
    /// else is `.plain`. `display` keeps original spacing/punctuation; `lookup`
    /// is the matched text used for the saved-check and capture.
    private var renderTokens: [Token] {
        let atoms = PhraseSpanMatcher.atoms(sentence)
        // Map each atom index → its word index (or nil for separators).
        var wordIndexOfAtom: [Int?] = []
        var words: [String] = []
        for a in atoms {
            if a.isWord { wordIndexOfAtom.append(words.count); words.append(a.text) }
            else { wordIndexOfAtom.append(nil) }
        }
        let spans = PhraseSpanMatcher.spans(words: words, phrases: knownPhrases)
        // wordIndex → the span covering it (if any).
        var spanOfWord: [Int: Range<Int>] = [:]
        for s in spans { for w in s { spanOfWord[w] = s } }

        var tokens: [Token] = []
        var i = 0
        while i < atoms.count {
            let atom = atoms[i]
            if atom.isWord, let wi = wordIndexOfAtom[i], let span = spanOfWord[wi], wi == span.lowerBound {
                // Start of a phrase span: consume atoms through the last word of the span.
                var display = ""
                var lastWordAtom = i
                var j = i
                while j < atoms.count {
                    if let wj = wordIndexOfAtom[j], span.contains(wj) { lastWordAtom = j }
                    if let wj = wordIndexOfAtom[j], wj >= span.upperBound { break }
                    display += atoms[j].text
                    j += 1
                    if let wprev = wordIndexOfAtom[lastWordAtom], wprev == span.upperBound - 1,
                       j < atoms.count, wordIndexOfAtom[j] != nil { break }
                }
                tokens.append(Token(display: display, lookup: trimmed(display), kind: .phrase))
                i = j
            } else if atom.isWord {
                tokens.append(Token(display: atom.text, lookup: atom.text, kind: .word))
                i += 1
            } else {
                tokens.append(Token(display: atom.text, lookup: atom.text, kind: .plain))
                i += 1
            }
        }
        return tokens
    }

    private func trimmed(_ s: String) -> String {
        s.trimmingCharacters(in: CharacterSet(charactersIn: " \t"))
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
