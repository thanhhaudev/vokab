import Foundation

/// Pure geometry helper for resizable panes — kept in VokabKit so it is
/// unit-tested offline (the App target has no test target).
public enum PaneWidth {
    public static func clamp(_ x: Double, to range: ClosedRange<Double>) -> Double {
        min(range.upperBound, max(range.lowerBound, x))
    }

    /// Result of splitting the list+detail content area: the list width, the
    /// detail width, and the range the list↔detail divider may drag within.
    public struct Panes: Equatable {
        public let list: Double
        public let detail: Double
        public let dragRange: ClosedRange<Double>
        public init(list: Double, detail: Double, dragRange: ClosedRange<Double>) {
            self.list = list
            self.detail = detail
            self.dragRange = dragRange
        }
    }

    /// Divide the Library's list↔detail content area.
    ///
    /// The split is driven by `listFraction` (the list's share of the content
    /// area, 0…1) rather than an absolute width, so the proportion stays balanced
    /// across window sizes. The divider drags freely in both directions: the list
    /// can range from `listMin` up to whatever leaves the detail its `detailMin`
    /// — there is deliberately no upper cap on the detail, so the user can make
    /// either pane the larger one.
    ///
    /// When the window is too narrow to satisfy both minimums, the list keeps its
    /// floor and the detail absorbs whatever remains — and `dragRange` collapses
    /// to a single point so the divider stays put (a degenerate `ClosedRange`
    /// with lower > upper would trap).
    public static func split(
        available: Double,
        sidebar: Double,
        listFraction: Double,
        dividerGap: Double = 12,
        listMin: Double = 240,
        detailMin: Double = 360
    ) -> Panes {
        let content = max(0, available - dividerGap - sidebar)
        let hi = content - detailMin                       // widest list (detail ≥ min)
        let lo = listMin                                   // narrowest list
        guard hi > lo else {
            let list = min(listMin, content)
            return Panes(list: list, detail: max(0, content - list), dragRange: list...list)
        }
        let list = clamp(content * listFraction, to: lo...hi)
        return Panes(list: list, detail: content - list, dragRange: lo...hi)
    }
}
