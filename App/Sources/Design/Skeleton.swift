import SwiftUI

/// A moving-gradient shimmer over redacted placeholder content, matching the
/// app's light, hairline aesthetic. Honors Reduce Motion: when on, it shows
/// static redaction with no animation.
struct SkeletonModifier: ViewModifier {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var phase: CGFloat = -1

    func body(content: Content) -> some View {
        content
            .redacted(reason: .placeholder)
            .overlay {
                if !reduceMotion {
                    GeometryReader { geo in
                        LinearGradient(
                            colors: [.clear, .white.opacity(0.65), .clear],
                            startPoint: .leading, endPoint: .trailing)
                            .frame(width: geo.size.width * 1.5)
                            .offset(x: phase * geo.size.width * 1.5)
                    }
                    .allowsHitTesting(false)
                    // Confine the bright sweep to the gray redaction bars so it
                    // reads as a shimmer on the light background, not over whitespace.
                    .mask(content.redacted(reason: .placeholder))
                }
            }
            .onAppear {
                guard !reduceMotion else { return }
                withAnimation(.linear(duration: 1.2).repeatForever(autoreverses: false)) {
                    phase = 1
                }
            }
            .onDisappear { phase = -1 }
    }
}

extension View {
    /// Renders the view as an animated skeleton placeholder.
    func skeleton() -> some View { modifier(SkeletonModifier()) }
}
