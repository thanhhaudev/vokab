import AppKit

/// The brand "V" chevron rendered for the menubar.
///
/// Geometry mirrors `App/Resources/AppIcon.svg`: the path `M 182 166 L 256 256
/// L 330 166` (round cap/join) in a 512×512 space. The V is drawn at one fixed
/// size in both states via `glyphRect` so it never shrinks/grows.
///
/// Both `idle()` and `processingGlyph()` are **template** images, so macOS tints
/// the V per-screen (white on the active menubar, black/dimmed on the others).
/// `processingGlyph()` is a WIDER canvas: the V stays in the left 18pt region and
/// the right region is transparent, reserving room for the amber activity dot.
///
/// The dot is NOT drawn into the image (a colored dot would force the whole image
/// non-template, defeating per-screen tinting — the original bug). Instead
/// `StatusItemController` draws the dot as a separate amber `CALayer` over the
/// status button, positioned via `dotFrame`. The V and the dot are thus two
/// independent layers: the V auto-tints, the dot keeps its amber color.
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

    /// Amber activity dot color (#EF9F27, sRGB). Used by `StatusItemController`
    /// for the overlay layer; never drawn into the (template) image.
    static let dotColor = NSColor(srgbRed: 0xEF / 255.0, green: 0x9F / 255.0,
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

    /// Size of the wider processing canvas: V's 18pt region plus room for the dot.
    static var processingSize: NSSize {
        NSSize(width: (glyphRightEdge + dotGap) + dotDiameter + dotTrailing, height: size.height)
    }

    /// The amber dot's frame within the `processingSize` canvas (origin bottom-left).
    /// `StatusItemController` maps this into the status button to place the layer,
    /// so the dot lands in the same lower-right notch ("V.") as before.
    static var dotFrame: NSRect {
        NSRect(x: glyphRightEdge + dotGap, y: glyphBaseline, width: dotDiameter, height: dotDiameter)
    }

    /// Wide-canvas **template** V (no dot, no manual color): the V occupies the
    /// left 18pt region — identical placement to `idle()` — and the right region is
    /// transparent. Template, so macOS tints the V per-screen. The amber dot is
    /// drawn separately by `StatusItemController` as a `CALayer`.
    static func processingGlyph() -> NSImage {
        let image = NSImage(size: processingSize, flipped: false) { rect in
            let vRegion = NSRect(x: 0, y: 0, width: size.width, height: rect.height)
            drawChevron(in: glyphRect(in: vRegion), color: .black)
            return true
        }
        image.isTemplate = true
        return image
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
