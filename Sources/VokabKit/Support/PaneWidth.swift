import Foundation

/// Pure geometry helper for resizable panes — kept in VokabKit so it is
/// unit-tested offline (the App target has no test target).
public enum PaneWidth {
    public static func clamp(_ x: Double, to range: ClosedRange<Double>) -> Double {
        min(range.upperBound, max(range.lowerBound, x))
    }
}
