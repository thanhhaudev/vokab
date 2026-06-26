import SwiftUI
import AppKit
import VokabKit

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
        dyn(light: 0x0C447C, dark: 0x5B9BD5),   // 0 Academic
        dyn(light: 0x085041, dark: 0x4FBF96),   // 1 Business
        dyn(light: 0x854F0B, dark: 0xD89A4A),   // 2 Daily life
        dyn(light: 0x3C3489, dark: 0x9189E8),   // 3 Technology
        dyn(light: 0x1D6FB0, dark: 0x5BAEE0),   // 4 Science
        dyn(light: 0x7A4069, dark: 0xC07FAB),   // 5 Arts & Culture
        dyn(light: 0xB7484A, dark: 0xE08385),   // 6 News & Politics
        dyn(light: 0x1D9E75, dark: 0x46C9A0),   // 7 Travel
        dyn(light: 0x0F6E56, dark: 0x4FC59E),   // 8 Health
        dyn(light: 0x633806, dark: 0xCD9A5B),   // 9 Slang & Informal
        dyn(light: 0x712B13, dark: 0xCF8B6F),   // 10 Idioms & Expressions
        dyn(light: 0x534AB7, dark: 0x8A82E8),   // 11 dynamic / overflow
    ]

    static func categoryColor(_ index: Int) -> Color {
        categoryPalette[((index % categoryPalette.count) + categoryPalette.count) % categoryPalette.count]
    }

    // Highlight (paragraph source) + danger card
    static let highlightBg = dyn(light: 0xFAEEDA, dark: 0x3A3322)
    static let highlightText = dyn(light: 0x633806, dark: 0xE0B978)

    // Radii
    static let radiusMd: CGFloat = 8
    static let radiusLg: CGFloat = 12
    static let radiusXl: CGFloat = 16

    /// Width of a hairline border/divider: exactly one physical device pixel.
    /// A fixed 0.5pt rounds down to 0px on a scaled display whose backing scale
    /// is 1 (resolution set below native), so the stroke renders incomplete —
    /// the same bug fixed in `Hairline`. `1/displayScale` is always one device
    /// pixel: crisp everywhere, identical to 0.5pt at @2x. Read `displayScale`
    /// from the environment at the call site and pass it in.
    static func hairline(_ scale: CGFloat) -> CGFloat { 1.0 / max(scale, 1) }

    // Fonts
    static func mono(_ size: CGFloat, weight: Font.Weight = .regular) -> Font {
        .system(size: size, weight: weight, design: .monospaced)
    }

    // MARK: Part-of-speech token colors (phrase tokens only — NOT pills)
    static func posColors(_ pos: String?) -> (fg: Color, bg: Color) {
        switch normalizePOS(pos) {
        case "verb": return (dyn(light: 0x3C3489, dark: 0xC8C2F5), dyn(light: 0xEEEDFE, dark: 0x2E2A52))
        case "noun": return (dyn(light: 0x085041, dark: 0x6FD3B0), dyn(light: 0xE1F5EE, dark: 0x163A30))
        case "prep": return (dyn(light: 0x633806, dark: 0xE0B978), dyn(light: 0xFAEEDA, dark: 0x3A3322))
        case "adv":  return (dyn(light: 0x712B13, dark: 0xE0A48A), dyn(light: 0xFAECE7, dark: 0x3A2820))
        default:     return (dyn(light: 0x3C3489, dark: 0xC8C2F5), dyn(light: 0xEEEDFE, dark: 0x2E2A52))
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
        case .overdue: return dyn(light: 0xD85A30, dark: 0xF0784A)
        case .today:   return dyn(light: 0xEF9F27, dark: 0xF5B84A)
        case .new:     return dyn(light: 0x1D9E75, dark: 0x35C495)
        case .future:  return dyn(light: 0xBFBFBF, dark: 0x6A6A66)
        }
    }
}

extension Theme.DueStatus {
    /// Maps a review state to a due bucket. Pure; nil or never-reviewed → `.new`.
    /// This is the single source of truth shared by the library list, the menubar,
    /// and the inline lookup popover.
    static func of(_ state: ReviewState?, now: Date) -> Theme.DueStatus {
        guard let s = state else { return .new }
        if s.reviewCount == 0 { return .new }
        if s.dueDate < Calendar.current.startOfDay(for: now) { return .overdue }
        if s.dueDate <= now.addingTimeInterval(86_400) { return .today }
        return .future
    }
}

extension Theme {
    // MARK: SM-2 grade colors
    static func gradeColor(_ grade: ReviewGradeKind) -> Color {
        switch grade {
        case .again: return dyn(light: 0xA32D2D, dark: 0xE57373)
        case .hard:  return dyn(light: 0x854F0B, dark: 0xD89A4A)
        case .good:  return dyn(light: 0x0F6E56, dark: 0x4FC59E)
        case .easy:  return dyn(light: 0x3C3489, dark: 0x9189E8)
        }
    }

    // Diff colors (production card)
    static let diffDel = dyn(light: 0xA32D2D, dark: 0xE57373)
    static let diffIns = dyn(light: 0x0F6E56, dark: 0x4FC59E)

    // Suggested SR button (production)
    static let sugBorder = dyn(light: 0x1D9E75, dark: 0x2FB98C)
    static let sugBg = dyn(light: 0xE1F5EE, dark: 0x1E3A33)

    // Shared status tokens (badges / pills / feedback boxes)
    static let successFg = dyn(light: 0x27500A, dark: 0x9BC47A)   // green text
    static let successBg = dyn(light: 0xEAF3DE, dark: 0x2A3322)
    static let saveFg = dyn(light: 0x085041, dark: 0x6FD3B0)      // phrase/teal green
    static let saveBg = dyn(light: 0xE1F5EE, dark: 0x163A30)
    static let warnFg = dyn(light: 0x854F0B, dark: 0xE0B978)      // amber
    static let warnBg = dyn(light: 0xFAEEDA, dark: 0x3A3322)
    static let infoFg = dyn(light: 0x0C447C, dark: 0x5B9BD5)      // blue
    static let infoBg = dyn(light: 0xE6F1FB, dark: 0x16314A)
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
