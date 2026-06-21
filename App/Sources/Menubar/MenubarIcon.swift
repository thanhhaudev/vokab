import AppKit

/// The brand "V" chevron rendered for the menubar.
///
/// Geometry mirrors `App/Resources/AppIcon.svg`: the path `M 182 166 L 256 256
/// L 330 166` (round cap/join) in a 512×512 space. `idle()` is a template image
/// so the system tints it for the light/dark menubar; `processing()` (Task 5)
/// adds the amber activity dot and is therefore non-template.
enum MenubarIcon {
    /// Logical menubar icon height in points; the system scales for Retina.
    private static let size = NSSize(width: 18, height: 18)

    /// Template V — system-tinted (black/white/accent) to match the menubar.
    static func idle() -> NSImage {
        let image = NSImage(size: size, flipped: false) { rect in
            drawChevron(in: rect, color: .black)
            return true
        }
        image.isTemplate = true
        return image
    }

    /// V + amber activity dot. Non-template (it carries color), so the V is
    /// stroked in the menubar's current text color to stay visible in light/dark.
    static func processing() -> NSImage {
        let amber = NSColor(srgbRed: 0xEF / 255.0, green: 0x9F / 255.0, blue: 0x27 / 255.0, alpha: 1)
        let image = NSImage(size: size, flipped: false) { rect in
            // Leave room at lower-right for the dot so the V doesn't overlap it.
            let vRect = NSRect(x: rect.minX, y: rect.minY + rect.height * 0.18,
                               width: rect.width * 0.82, height: rect.height * 0.82)
            drawChevron(in: vRect, color: .labelColor)
            let d = rect.width * 0.34
            let dot = NSRect(x: rect.maxX - d, y: rect.minY, width: d, height: d)
            amber.setFill()
            NSBezierPath(ovalIn: dot).fill()
            return true
        }
        image.isTemplate = false
        return image
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
