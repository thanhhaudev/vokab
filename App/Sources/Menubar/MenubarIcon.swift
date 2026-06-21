import AppKit

/// The brand "V" chevron rendered for the menubar.
///
/// Geometry mirrors `App/Resources/AppIcon.svg`: the path `M 182 166 L 256 256
/// L 330 166` (round cap/join) in a 512×512 space. The V is drawn at one fixed
/// size in both states via `glyphRect` so it never shrinks/grows.
///
/// `idle()` is a template image (system-tinted for light/dark). `processing()`
/// is a WIDER single image carrying the V plus an amber activity dot beside it.
/// It must be one image, not a composed SwiftUI label: `MenuBarExtra` renders
/// its label into a single icon-sized slot and clips any extra horizontal
/// content, so an `HStack { Image; Circle }` loses the dot. Because the dot
/// carries color, the whole image is non-template and the V is tinted manually.
enum MenubarIcon {
    /// Logical size of the idle V region; the system scales for Retina.
    private static let size = NSSize(width: 18, height: 18)

    /// Target box width for the V glyph inside the 18pt-wide region. Narrower than
    /// the full region for a lighter, more native weight (the V is the dominant,
    /// width-bound dimension of the chevron). Used by BOTH states.
    private static let glyphWidth: CGFloat = 15

    /// Diameter (pt) of the amber activity dot beside the V while analyzing.
    private static let dotDiameter: CGFloat = 5
    /// Gap (pt) from the V glyph's right edge to the dot (negative tucks it in).
    private static let dotGap: CGFloat = -0.5
    /// Right padding (pt) after the dot.
    private static let dotTrailing: CGFloat = 1

    /// X of the V glyph's right edge (incl. round cap) when centered in the 18pt
    /// region: derived from the chevron-fit math (offX + bbox·scale simplifies to
    /// `8 + glyphWidth/2`). Lets the dot track the glyph as its size changes.
    private static var glyphRightEdge: CGFloat { 8 + glyphWidth / 2 }

    /// Y of the V glyph's lowest pixel (the vertex's round-cap bottom) in the 18pt
    /// region. From the same fit math this simplifies to `offY` = `9 − 63·scale`,
    /// with `scale = (glyphWidth−2)/184`. The dot rests on this so the V and the
    /// dot share a baseline ("V."). `dotBaselineNudge` drops it ~1pt for optical
    /// alignment (the round-cap math reads slightly high to the eye).
    private static let dotBaselineNudge: CGFloat = 1
    private static var glyphBaseline: CGFloat { 9 - 63 * (glyphWidth - 2) / 184 - dotBaselineNudge }

    /// Amber activity dot color (#EF9F27, sRGB).
    private static let dotColor = NSColor(srgbRed: 0xEF / 255.0, green: 0x9F / 255.0,
                                          blue: 0x27 / 255.0, alpha: 1)

    /// Template V — system-tinted (black/white/accent) to match the menubar.
    static func idle() -> NSImage {
        let image = NSImage(size: size, flipped: false) { rect in
            drawChevron(in: glyphRect(in: rect), color: .black)
            return true
        }
        image.isTemplate = true
        return image
    }

    /// V (same fixed size as idle) plus an amber activity dot to its right, in a
    /// wider canvas. Non-template (carries color), so the V is stroked in the
    /// menubar's current foreground color to stay visible in light/dark.
    /// `pulse` is the dot's alpha (0…1), animated by `AppEnvironment` for a breath.
    static func processing(pulse: CGFloat = 1.0) -> NSImage {
        let dotX = glyphRightEdge + dotGap
        let width = dotX + dotDiameter + dotTrailing
        let image = NSImage(size: NSSize(width: width, height: size.height), flipped: false) { rect in
            // V occupies the left 18pt region — identical placement to idle, so the
            // glyph stays put and only the dot extends the item rightward.
            let vRegion = NSRect(x: 0, y: 0, width: size.width, height: rect.height)
            drawChevron(in: glyphRect(in: vRegion), color: systemMenubarForeground())
            // Dot resting on the V's baseline, tucked into the lower-right notch ("V.").
            let dot = NSRect(x: dotX, y: glyphBaseline, width: dotDiameter, height: dotDiameter)
            dotColor.withAlphaComponent(max(0, min(1, pulse))).setFill()
            NSBezierPath(ovalIn: dot).fill()
            return true
        }
        image.isTemplate = false
        return image
    }

    /// The menu bar's foreground color. We can't use NSApp.effectiveAppearance or
    /// a dynamic color (NSColor.labelColor): the app forces NSApp.appearance = .aqua,
    /// so both would always resolve to the light-mode (black) value. Read the system
    /// Dark Mode setting directly instead, which the forced app appearance does not affect.
    private static func systemMenubarForeground() -> NSColor {
        let dark = UserDefaults.standard.string(forKey: "AppleInterfaceStyle") == "Dark"
        return dark ? .white : .black
    }

    /// Centered sub-rect sizing the V to a native ~15pt-wide weight inside `rect`.
    private static func glyphRect(in rect: NSRect) -> NSRect {
        let dx = max(0, (rect.width - glyphWidth) / 2)
        return rect.insetBy(dx: dx, dy: 0)
    }

    /// Strokes the V chevron centered in `rect`, scaled from the SVG's 512 space.
    static func drawChevron(in rect: NSRect, color: NSColor) {
        // SVG points in 512 space: left top, bottom vertex, right top.
        let p1 = CGPoint(x: 182, y: 166), p2 = CGPoint(x: 256, y: 256), p3 = CGPoint(x: 330, y: 166)
        // Bounding box of the stroke path in 512 space (incl. the 36px stroke radius).
        let half = 36.0 / 2
        let minX = p1.x - half, maxX = p3.x + half
        let minY = p1.y - half, maxY = p2.y + half
        let bw = maxX - minX, bh = maxY - minY

        // Fit the path's bbox into rect with a small inset, preserving aspect.
        let inset: CGFloat = 1
        let avail = NSRect(x: rect.minX + inset, y: rect.minY + inset,
                           width: rect.width - inset * 2, height: rect.height - inset * 2)
        let scale = min(avail.width / bw, avail.height / bh)
        let drawnW = bw * scale, drawnH = bh * scale
        let offX = avail.minX + (avail.width - drawnW) / 2
        let offY = avail.minY + (avail.height - drawnH) / 2

        // SVG y grows downward; AppKit y grows upward → flip y within the bbox.
        func map(_ p: CGPoint) -> CGPoint {
            CGPoint(x: offX + (p.x - minX) * scale,
                    y: offY + (maxY - p.y) * scale)
        }

        let path = NSBezierPath()
        path.move(to: map(p1))
        path.line(to: map(p2))
        path.line(to: map(p3))
        path.lineWidth = 36 * scale
        path.lineCapStyle = .round
        path.lineJoinStyle = .round
        color.setStroke()
        path.stroke()
    }
}
