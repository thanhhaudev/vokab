import SwiftUI

/// Three dots gently fading in a staggered wave (opacity only — no movement).
/// The app's single inline "working…" indicator: capture toast, button actions,
/// any transient/indeterminate fetch with no content shape. Honors Reduce Motion
/// (static dots). For content whose shape is known, use `.skeleton()` instead.
struct ActivityDots: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var animating = false

    var diameter: CGFloat = 5
    var color: Color = Theme.dyn(light: 0x7F77DD, dark: 0x9D95E8)

    private let count = 3
    private let period = 0.5
    private let stagger = 0.16

    var body: some View {
        HStack(spacing: max(3, diameter * 0.8)) {
            ForEach(0..<count, id: \.self) { i in
                Circle()
                    .fill(color)
                    .frame(width: diameter, height: diameter)
                    .opacity(animating ? 1.0 : 0.25)
                    .animation(
                        reduceMotion ? nil :
                            .easeInOut(duration: period)
                            .repeatForever(autoreverses: true)
                            .delay(Double(i) * stagger),
                        value: animating)
            }
        }
        .frame(height: diameter)
        .onAppear { animating = true }
    }
}
