import AppKit
import SwiftUI

/// The brand "V" chevron rendered for the menubar.
///
/// Geometry mirrors `App/Resources/AppIcon.svg`: the path `M 182 166 L 256 256
/// L 330 166` (round cap/join) in a 512×512 space. `idle()` is the single source
/// of the glyph — a template image so the system tints it for the light/dark
/// menubar. The processing state adds an amber activity dot *beside* the V as a
/// SwiftUI `Circle` in the menubar label (see `VokabApp`), so the V never has to
/// carry color and stays a properly-tinted template at a fixed size.
enum MenubarIcon {
    /// Logical menubar icon height in points; the system scales for Retina.
    private static let size = NSSize(width: 18, height: 18)

    /// Target box width for the V glyph inside the 18pt-wide image. Narrower than
    /// the full image for a lighter, more native weight (the V is the dominant,
    /// width-bound dimension of the chevron).
    private static let glyphWidth: CGFloat = 17

    /// Diameter (pt) of the amber activity dot shown beside the V while analyzing.
    static let dotDiameter: CGFloat = 6
    /// Spacing (pt) between the V and the activity dot.
    static let dotGap: CGFloat = 2
    /// Amber activity dot color (#EF9F27, sRGB).
    static let activityDotColor = Color(red: 0xEF / 255.0, green: 0x9F / 255.0, blue: 0x27 / 255.0)

    /// Template V — system-tinted (black/white/accent) to match the menubar.
    /// Used in BOTH idle and processing states so the glyph size never changes.
    static func idle() -> NSImage {
        let image = NSImage(size: size, flipped: false) { rect in
            drawChevron(in: glyphRect(in: rect), color: .black)
            return true
        }
        image.isTemplate = true
        return image
    }

    /// Centered sub-rect sizing the V to a native ~15pt-wide weight. The image
    /// stays 18pt tall for correct menubar metrics; only the drawn glyph narrows.
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
