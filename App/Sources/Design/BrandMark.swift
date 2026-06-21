import SwiftUI

/// The brand "V" chevron from the app icon SVG (path `M 182 166 L 256 256 L 330 166`),
/// as a resolution-independent shape for in-app brand badges. The menubar uses the
/// AppKit twin in `MenubarIcon`; this keeps the on-screen mark identical to the icon.
struct BrandV: Shape {
    /// Fraction of the rect kept as padding so the round stroke caps don't clip.
    var inset: CGFloat = 0.26

    func path(in rect: CGRect) -> Path {
        let pad = min(rect.width, rect.height) * inset
        let r = rect.insetBy(dx: pad, dy: pad)
        // SVG points in 512 space. SwiftUI's y-axis grows downward like SVG's,
        // so the V points down with no flip (unlike the AppKit menubar version).
        let minX: CGFloat = 182, maxX: CGFloat = 330
        let minY: CGFloat = 166, maxY: CGFloat = 256
        let bw = maxX - minX, bh = maxY - minY
        let scale = min(r.width / bw, r.height / bh)
        let offX = r.minX + (r.width - bw * scale) / 2
        let offY = r.minY + (r.height - bh * scale) / 2
        func map(_ x: CGFloat, _ y: CGFloat) -> CGPoint {
            CGPoint(x: offX + (x - minX) * scale, y: offY + (y - minY) * scale)
        }
        var path = Path()
        path.move(to: map(182, 166))
        path.addLine(to: map(256, 256))
        path.addLine(to: map(330, 166))
        return path
    }
}

/// The purple brand badge — the V chevron on the accent square — matching the
/// mockup's app glyph. `size` is the square's side length.
struct BrandBadge: View {
    var size: CGFloat
    var corner: CGFloat

    var body: some View {
        BrandV()
            .stroke(Theme.accentBg,
                    style: StrokeStyle(lineWidth: size * 0.12, lineCap: .round, lineJoin: .round))
            .frame(width: size, height: size)
            .background(Theme.accent, in: RoundedRectangle(cornerRadius: corner))
    }
}
