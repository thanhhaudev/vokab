import SwiftUI
import VokabKit

/// Segmented type-override choice. `.auto` = let capture classify; otherwise force.
enum TypeChoice: CaseIterable {
    case auto, word, phrase, paragraph
    var forcedType: CardType? {
        switch self {
        case .auto: return nil
        case .word: return .word
        case .phrase: return .phrase
        case .paragraph: return .paragraphItem
        }
    }
    var label: String {
        switch self {
        case .auto: return L.t("Auto", "Auto")
        case .word: return L.t("Word", "Word")
        case .phrase: return L.t("Phrase", "Phrase")
        case .paragraph: return L.t("Para", "Para")
        }
    }
}

/// Colored pill showing the detected/forced capture type, with an optional word
/// count suffix. Tokens match mockup #9/#10.
struct DetectedTypePill: View {
    let type: CardType
    var count: Int? = nil

    private var spec: (bg: Color, fg: Color, icon: String, name: String) {
        switch type {
        case .word: return (Theme.accentBg, Theme.accentText, "textformat", L.t("Word", "Word"))
        case .phrase: return (Theme.saveBg, Theme.saveFg, "text.quote", L.t("Phrase", "Phrase"))
        case .paragraphItem: return (Theme.warnBg, Theme.highlightText, "text.alignleft", L.t("Paragraph", "Paragraph"))
        }
    }

    var body: some View {
        let s = spec
        let suffix = count.map { " · \($0) \(L.t("words", "từ"))" } ?? ""
        return HStack(spacing: 4) {
            Image(systemName: s.icon).font(.system(size: 10))
            Text(s.name + suffix).lineLimit(1)
        }
        .font(.system(size: 11, weight: .medium))
        .foregroundStyle(s.fg)
        .padding(.horizontal, 8).padding(.vertical, 3)
        .background(s.bg, in: Capsule())
        .fixedSize(horizontal: true, vertical: false)
    }
}

/// Segmented override control (mockup `.seg`). Configurable choices.
struct TypeOverrideSegmented: View {
    @Environment(\.displayScale) private var displayScale
    let choices: [TypeChoice]
    @Binding var selection: TypeChoice

    var body: some View {
        HStack(spacing: 0) {
            ForEach(Array(choices.enumerated()), id: \.offset) { idx, choice in
                let on = choice == selection
                Button { selection = choice } label: {
                    Text(choice.label)
                        .font(.system(size: 11, weight: on ? .medium : .regular))
                        .foregroundStyle(on ? Theme.accentText : Theme.textSecondary)
                        .padding(.horizontal, 9).padding(.vertical, 3)
                        .background(on ? Theme.accentBg : Theme.bgPrimary)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                if idx < choices.count - 1 {
                    // Explicit height: a width-only Rectangle is greedy vertically and
                    // would stretch the whole segmented (and its parent form) tall.
                    Rectangle().fill(Theme.borderTertiary).frame(width: Theme.hairline(displayScale), height: 18)
                }
            }
        }
        .fixedSize()   // size to content; never expand to fill the row/column
        .clipShape(RoundedRectangle(cornerRadius: 7))
        .overlay(RoundedRectangle(cornerRadius: 7).strokeBorder(Theme.borderSecondary, lineWidth: Theme.hairline(displayScale)))
    }
}

/// Language chip + dropdown (mockup "EN · auto ▾"). `selection == nil` = Auto
/// (NLP detect); otherwise a forced BCP-47-ish code. `detected` is shown when Auto.
struct LanguageMenu: View {
    @Environment(\.displayScale) private var displayScale
    @Binding var selection: String?
    let detected: String

    static let options = ["en", "vi", "es", "fr", "de", "ja", "zh"]

    var body: some View {
        Menu {
            Button(L.t("Auto", "Auto")) { selection = nil }
            Divider()
            ForEach(Self.options, id: \.self) { code in
                Button(code.uppercased()) { selection = code }
            }
        } label: {
            HStack(spacing: 3) {
                Image(systemName: "flag").font(.system(size: 10))
                Text(selection?.uppercased() ?? "\(detected.uppercased()) · \(L.t("auto", "auto"))")
                Image(systemName: "chevron.down").font(.system(size: 9))
            }
            .font(.system(size: 11))
            .foregroundStyle(Theme.textSecondary)
            .padding(.horizontal, 7).padding(.vertical, 2)
            .background(Theme.bgPrimary, in: RoundedRectangle(cornerRadius: 6))
            .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(Theme.borderSecondary, lineWidth: Theme.hairline(displayScale)))
        }
        .menuStyle(.borderlessButton).fixedSize()
    }
}
