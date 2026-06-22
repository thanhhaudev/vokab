import SwiftUI

// MARK: - Pills (semantic, per mockup: CEFR / type / register)

enum PillStyle {
    case cefr(String)   // colored by level
    case type           // purple — part of speech / phrase type
    case register       // green — register/formality

    var bg: Color {
        switch self {
        case .cefr(let level): return Self.cefrColors(level).bg
        case .type: return Theme.accentBg
        case .register: return Theme.successBg
        }
    }
    var fg: Color {
        switch self {
        case .cefr(let level): return Self.cefrColors(level).fg
        case .type: return Theme.accentText
        case .register: return Theme.successFg
        }
    }

    /// CEFR pill color by level (A–B green, C1 blue, C2 purple) per the mockup.
    static func cefrColors(_ level: String) -> (fg: Color, bg: Color) {
        switch level.lowercased() {
        case "c1": return (Theme.infoFg, Theme.infoBg)            // blue
        case "c2": return (Theme.accentText, Theme.accentBg)      // purple
        default:   return (Theme.successFg, Theme.successBg)      // green (A–B)
        }
    }
}

struct Pill: View {
    let text: String
    let style: PillStyle
    init(_ text: String, style: PillStyle) { self.text = text; self.style = style }

    /// Convenience for a CEFR pill — extracts the bare level (A1–C2) from a
    /// possibly-verbose string so it never balloons.
    static func cefr(_ raw: String) -> Pill {
        let level = raw.cefrLevel ?? String(raw.prefix(2)).uppercased()
        return Pill(level, style: .cefr(level))
    }

    var body: some View {
        Text(text)
            .font(.system(size: 11))
            .lineLimit(1)                    // never wrap into a blob
            .fixedSize(horizontal: true, vertical: false)
            .padding(.horizontal, 8).padding(.vertical, 2)
            .background(style.bg, in: Capsule())
            .foregroundStyle(style.fg)
    }
}

/// Renders 0..n short pills from a possibly multi-value string ("formal /
/// business" → two pills), dropping overly long fragments.
struct MultiPill: View {
    let raw: String?
    let style: PillStyle
    init(_ raw: String?, style: PillStyle) { self.raw = raw; self.style = style }

    var body: some View {
        HStack(spacing: 4) {
            ForEach((raw ?? "").pillTokens(), id: \.self) { Pill($0, style: style) }
        }
    }
}

extension String {
    /// The bare CEFR level (A1–C2) found in the string, uppercased, or nil.
    var cefrLevel: String? {
        guard let r = range(of: "[ABCabc][12]", options: .regularExpression) else { return nil }
        return String(self[r]).uppercased()
    }

    /// Splits a field like "formal / business; neutral" into trimmed short
    /// tokens, dropping empty or verbose (> maxLen) fragments.
    func pillTokens(maxTokens: Int = 3, maxLen: Int = 16) -> [String] {
        let tokens = split(whereSeparator: { "/,;|".contains($0) })
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty && $0.count <= maxLen }
        return Array(tokens.prefix(maxTokens))
    }
}

// MARK: - Chip (outlined, clickable-looking)

struct Chip: View {
    @Environment(\.displayScale) private var displayScale
    let text: String
    init(_ text: String) { self.text = text }
    var body: some View {
        Text(text)
            .font(.system(size: 12))
            .padding(.horizontal, 10).padding(.vertical, 4)
            .background(Theme.bgPrimary, in: Capsule())
            .overlay(Capsule().strokeBorder(Theme.borderSecondary, lineWidth: Theme.hairline(displayScale)))
            .foregroundStyle(Theme.textSecondary)
    }
}

// MARK: - Section label (uppercase tertiary)

struct SecLabel: View {
    let text: String
    init(_ text: String) { self.text = text }
    var body: some View {
        Text(text.uppercased())
            .font(.system(size: 11, weight: .regular))
            .tracking(0.6)
            .foregroundStyle(Theme.textTertiary)
    }
}

// MARK: - Due dot

struct DueDot: View {
    let status: Theme.DueStatus
    var size: CGFloat = 7
    var body: some View {
        Circle().fill(Theme.dueColor(status)).frame(width: size, height: size)
    }
}

// MARK: - Hairline divider

struct Hairline: View {
    @Environment(\.displayScale) private var displayScale
    var body: some View {
        // Exactly one device pixel. A fixed 0.5pt rounds down to 0px on a
        // scaled display whose backing scale is 1 (e.g. resolution set below
        // native), making the line disappear. 1/displayScale is always one
        // physical pixel — crisp everywhere, and identical to 0.5pt on Retina.
        Rectangle().fill(Theme.borderTertiary)
            .frame(height: 1.0 / max(displayScale, 1))
    }
}

// MARK: - Window card container (white, hairline border, rounded)

struct WinCard<Content: View>: View {
    @Environment(\.displayScale) private var displayScale
    @ViewBuilder var content: Content
    var body: some View {
        VStack(spacing: 0) { content }
            .background(Theme.bgPrimary)
            .clipShape(RoundedRectangle(cornerRadius: Theme.radiusLg))
            .overlay(RoundedRectangle(cornerRadius: Theme.radiusLg)
                .strokeBorder(Theme.borderTertiary, lineWidth: Theme.hairline(displayScale)))
    }
}

// MARK: - Buttons

struct VPrimaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 13, weight: .medium))
            .padding(.horizontal, 14).padding(.vertical, 5)
            .background(Theme.accent.opacity(configuration.isPressed ? 0.85 : 1), in: RoundedRectangle(cornerRadius: Theme.radiusMd))
            .foregroundStyle(Theme.accentBg)
    }
}

struct VSecondaryButtonStyle: ButtonStyle {
    // ButtonStyle is not a View, so @Environment doesn't update here — read
    // displayScale inside a real View so the hairline border stays one pixel.
    func makeBody(configuration: Configuration) -> some View {
        StyledLabel(configuration: configuration)
    }

    private struct StyledLabel: View {
        @Environment(\.displayScale) private var displayScale
        let configuration: Configuration
        var body: some View {
            configuration.label
                .font(.system(size: 13))
                .padding(.horizontal, 14).padding(.vertical, 5)
                .background(Theme.bgPrimary.opacity(configuration.isPressed ? 0.7 : 1), in: RoundedRectangle(cornerRadius: Theme.radiusMd))
                .overlay(RoundedRectangle(cornerRadius: Theme.radiusMd).strokeBorder(Theme.borderSecondary, lineWidth: Theme.hairline(displayScale)))
                .foregroundStyle(Theme.textPrimary)
        }
    }
}

extension ButtonStyle where Self == VPrimaryButtonStyle {
    static var vPrimary: VPrimaryButtonStyle { VPrimaryButtonStyle() }
}
extension ButtonStyle where Self == VSecondaryButtonStyle {
    static var vSecondary: VSecondaryButtonStyle { VSecondaryButtonStyle() }
}

// MARK: - Titlebar (traffic lights + title) for in-content window chrome

struct FauxTitlebar: View {
    let title: String
    var trailing: String? = nil
    var body: some View {
        HStack(spacing: 8) {
            Circle().fill(Color(hex: 0xFF5F57)).frame(width: 11, height: 11)
            Circle().fill(Color(hex: 0xFEBC2E)).frame(width: 11, height: 11)
            Circle().fill(Color(hex: 0x28C840)).frame(width: 11, height: 11)
            Text(title).font(.system(size: 13)).foregroundStyle(Theme.textSecondary).padding(.leading, 4)
            Spacer()
            if let trailing {
                Text(trailing).font(.system(size: 12)).foregroundStyle(Theme.textTertiary)
            }
        }
        .padding(.horizontal, 14).padding(.vertical, 10)
        .background(Theme.bgSecondary)
        .overlay(alignment: .bottom) { Hairline() }
    }
}
