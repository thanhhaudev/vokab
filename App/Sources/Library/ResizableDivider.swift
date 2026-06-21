import SwiftUI
import VokabKit

/// A crisp 1px divider with a wider invisible hit area that drag-resizes the
/// bound width within `range`. Shows a left/right resize cursor on hover.
/// `width` is a live @State in the parent (cheap to update each frame); the
/// parent persists it via `onCommit` only when the drag ends — writing
/// UserDefaults every frame caused visible jank.
struct ResizableDivider: View {
    @Binding var width: Double
    let range: ClosedRange<Double>
    /// The width currently rendered, which can exceed `width` when the pane is
    /// absorbing surplus space (list "ăn dư"). Used as the drag origin so the
    /// first drag tick doesn't snap back to the stored `width`.
    var baseline: Double?
    var onCommit: (Double) -> Void = { _ in }

    @State private var dragStart: Double?
    @State private var hovering = false

    init(width: Binding<Double>, range: ClosedRange<Double>, baseline: Double? = nil,
         onCommit: @escaping (Double) -> Void = { _ in }) {
        self._width = width
        self.range = range
        self.baseline = baseline
        self.onCommit = onCommit
    }

    var body: some View {
        Rectangle()
            .fill(Theme.borderSecondary)
            .frame(width: 1)
            .frame(maxHeight: .infinity)
            // Wider transparent grab area, overflowing the 1px line (does not
            // shift the layout — the divider stays a crisp 1px column).
            .overlay(Color.clear.frame(width: 9).contentShape(Rectangle()))
            .onHover { inside in
                // Guard so push/pop stays balanced (onHover can re-fire while the
                // divider reframes under the cursor during a drag → cursor flicker).
                if inside {
                    if !hovering { hovering = true; NSCursor.resizeLeftRight.push() }
                } else {
                    if hovering { hovering = false; NSCursor.pop() }
                }
            }
            .gesture(
                // .global coordinate space is essential: the divider moves as the
                // width changes, so a .local translation would feed its own motion
                // back into the delta and the drag would oscillate/shake.
                DragGesture(minimumDistance: 1, coordinateSpace: .global)
                    .onChanged { value in
                        let start = dragStart ?? baseline ?? width
                        if dragStart == nil { dragStart = start }
                        width = PaneWidth.clamp(start + Double(value.translation.width), to: range)
                    }
                    .onEnded { _ in
                        dragStart = nil
                        onCommit(width)
                    }
            )
    }
}
