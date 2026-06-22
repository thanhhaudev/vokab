import SwiftUI
import AppKit

/// Design tokens transcribed from `docs/mockups/mockups.html` so the SwiftUI app
/// reproduces the mockup faithfully. The mockup is light-only; colors are
/// explicit (not system semantic) so the look is identical regardless of the
/// host appearance.
enum Theme {
    /// Resolves `light`/`dark` against the drawing view's effective appearance,
    /// so a single static token re-resolves when the window flips light↔dark.
    static func dyn(_ light: Color, _ dark: Color) -> Color {
        Color(nsColor: NSColor(name: nil) { ap in
            let isDark = ap.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
            return NSColor(isDark ? dark : light)
        })
    }
    static func dyn(light: UInt32, dark: UInt32) -> Color {
        dyn(Color(hex: light), Color(hex: dark))
    }

    // Backgrounds
    static let bgPrimary = dyn(light: 0xFFFFFF, dark: 0x1E1E1C)
    static let bgSecondary = dyn(light: 0xF6F5F0, dark: 0x262521)
    static let bgTertiary = dyn(light: 0xEEECE3, dark: 0x302E28)
    static let bgDanger = dyn(light: 0xFCEBEB, dark: 0x3A2422)

    // Text
    static let textPrimary = dyn(light: 0x1B1B18, dark: 0xF2F1EC)
    static let textSecondary = dyn(light: 0x605F59, dark: 0xB7B5AC)
    static let textTertiary = dyn(light: 0x92918A, dark: 0x86847C)
    static let textDanger = dyn(light: 0xA32D2D, dark: 0xE57373)

    // Hairline borders
    static let borderTertiary = dyn(.black.opacity(0.09), .white.opacity(0.12))
    static let borderSecondary = dyn(.black.opacity(0.16), .white.opacity(0.18))
    static let borderPrimary = dyn(.black.opacity(0.24), .white.opacity(0.26))

    // Accent
    static let accent = dyn(light: 0x534AB7, dark: 0x8A82E8)
    static let accentBg = dyn(light: 0xEEEDFE, dark: 0x2E2A52)
    static let accentText = dyn(light: 0x3C3489, dark: 0xC8C2F5)

    // Category dots/pills. Indexed by `categories.color_index`
    // (see `CategoryService.paletteSize` = 12). Seed categories map to indices
    // 0–10 IN SEED ORDER, so these colors must match the mockup's per-category
    // dots (surface #4): Academic #0C447C, Business #085041, Daily life #854F0B,
    // Technology #3C3489, …, Idioms & Expressions #712B13. Index 11 is for
    // agy-created categories beyond the seeds.
    static let categoryPalette: [Color] = [
        Color(hex: 0x0C447C),   // 0 Academic
        Color(hex: 0x085041),   // 1 Business
        Color(hex: 0x854F0B),   // 2 Daily life
        Color(hex: 0x3C3489),   // 3 Technology
        Color(hex: 0x1D6FB0),   // 4 Science
        Color(hex: 0x7A4069),   // 5 Arts & Culture
        Color(hex: 0xB7484A),   // 6 News & Politics
        Color(hex: 0x1D9E75),   // 7 Travel
        Color(hex: 0x0F6E56),   // 8 Health
        Color(hex: 0x633806),   // 9 Slang & Informal
        Color(hex: 0x712B13),   // 10 Idioms & Expressions
        Color(hex: 0x534AB7),   // 11 dynamic / overflow
    ]

    static func categoryColor(_ index: Int) -> Color {
        categoryPalette[((index % categoryPalette.count) + categoryPalette.count) % categoryPalette.count]
    }

    // Highlight (paragraph source) + danger card
    static let highlightBg = Color(hex: 0xFAEEDA)
    static let highlightText = Color(hex: 0x633806)

    // Radii
    static let radiusMd: CGFloat = 8
    static let radiusLg: CGFloat = 12
    static let radiusXl: CGFloat = 16
    static let hairline: CGFloat = 0.5

    // Fonts
    static func mono(_ size: CGFloat, weight: Font.Weight = .regular) -> Font {
        .system(size: size, weight: weight, design: .monospaced)
    }

    // MARK: Part-of-speech token colors (phrase tokens only — NOT pills)
    static func posColors(_ pos: String?) -> (fg: Color, bg: Color) {
        switch normalizePOS(pos) {
        case "verb": return (Color(hex: 0x3C3489), Color(hex: 0xEEEDFE))
        case "noun": return (Color(hex: 0x085041), Color(hex: 0xE1F5EE))
        case "prep": return (Color(hex: 0x633806), Color(hex: 0xFAEEDA))
        case "adv":  return (Color(hex: 0x712B13), Color(hex: 0xFAECE7))
        default:     return (Color(hex: 0x3C3489), Color(hex: 0xEEEDFE))
        }
    }

    private static func normalizePOS(_ pos: String?) -> String {
        guard let pos = pos?.lowercased() else { return "" }
        if pos.hasPrefix("verb") { return "verb" }
        if pos.hasPrefix("noun") { return "noun" }
        if pos.hasPrefix("prep") { return "prep" }
        if pos.hasPrefix("adv") { return "adv" }
        return ""
    }

    // MARK: Due-dot
    enum DueStatus { case overdue, today, new, future }
    static func dueColor(_ status: DueStatus) -> Color {
        switch status {
        case .overdue: return Color(hex: 0xD85A30)
        case .today:   return Color(hex: 0xEF9F27)
        case .new:     return Color(hex: 0x1D9E75)
        case .future:  return Color(hex: 0xBFBFBF)
        }
    }

    // MARK: SM-2 grade colors
    static func gradeColor(_ grade: ReviewGradeKind) -> Color {
        switch grade {
        case .again: return Color(hex: 0xA32D2D)
        case .hard:  return Color(hex: 0x854F0B)
        case .good:  return Color(hex: 0x0F6E56)
        case .easy:  return Color(hex: 0x3C3489)
        }
    }

    // Diff colors (production card)
    static let diffDel = Color(hex: 0xA32D2D)
    static let diffIns = Color(hex: 0x0F6E56)

    // Suggested SR button (production)
    static let sugBorder = Color(hex: 0x1D9E75)
    static let sugBg = Color(hex: 0xE1F5EE)
}

/// Local mirror of the grade kinds for color lookup without importing the model
/// into pure-view contexts.
enum ReviewGradeKind { case again, hard, good, easy }

extension Color {
    init(hex: UInt32) {
        let r = Double((hex >> 16) & 0xFF) / 255.0
        let g = Double((hex >> 8) & 0xFF) / 255.0
        let b = Double(hex & 0xFF) / 255.0
        self.init(.sRGB, red: r, green: g, blue: b, opacity: 1.0)
    }
}
