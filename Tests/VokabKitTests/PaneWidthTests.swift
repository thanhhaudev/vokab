import XCTest
@testable import VokabKit

final class PaneWidthTests: XCTestCase {
    func test_clamp_belowLower_returnsLower() {
        XCTAssertEqual(PaneWidth.clamp(100, to: 150...300), 150, accuracy: 0.0001)
    }
    func test_clamp_aboveUpper_returnsUpper() {
        XCTAssertEqual(PaneWidth.clamp(400, to: 150...300), 300, accuracy: 0.0001)
    }
    func test_clamp_inRange_returnsValue() {
        XCTAssertEqual(PaneWidth.clamp(200, to: 150...300), 200, accuracy: 0.0001)
    }
    func test_clamp_atBounds() {
        XCTAssertEqual(PaneWidth.clamp(150, to: 150...300), 150, accuracy: 0.0001)
        XCTAssertEqual(PaneWidth.clamp(300, to: 150...300), 300, accuracy: 0.0001)
    }

    // MARK: split

    /// The fraction sets a proportional, balanced split — the two panes sum to the
    /// content area and the list gets its share, with no upper cap on the detail.
    func test_split_proportional_balanced() {
        let p = PaneWidth.split(available: 1600, sidebar: 172, listFraction: 0.42)
        let content = 1600.0 - 12 - 172            // 1416
        XCTAssertEqual(p.list, content * 0.42, accuracy: 0.0001)
        XCTAssertEqual(p.list + p.detail, content, accuracy: 0.0001)
        XCTAssertGreaterThanOrEqual(p.detail, 360)
    }

    /// The same fraction yields the same proportion regardless of window size.
    func test_split_fractionScalesWithWindow() {
        let small = PaneWidth.split(available: 1100, sidebar: 172, listFraction: 0.5)
        let big = PaneWidth.split(available: 2000, sidebar: 172, listFraction: 0.5)
        XCTAssertEqual(small.list / (small.list + small.detail), 0.5, accuracy: 0.0001)
        XCTAssertEqual(big.list / (big.list + big.detail), 0.5, accuracy: 0.0001)
    }

    /// Dragging the list as wide as possible leaves the detail at its 360 floor.
    func test_split_listDraggedWide_detailKeepsMin() {
        let p = PaneWidth.split(available: 1600, sidebar: 172, listFraction: 0.99)
        XCTAssertEqual(p.detail, 360, accuracy: 0.0001)
        XCTAssertEqual(p.dragRange.upperBound, p.list, accuracy: 0.0001)
    }

    /// Dragging the list as narrow as possible leaves it at the 240 floor — and
    /// the detail is now the larger pane (no upper cap on detail).
    func test_split_listDraggedNarrow_detailGrows() {
        let p = PaneWidth.split(available: 1600, sidebar: 172, listFraction: 0.01)
        XCTAssertEqual(p.list, 240, accuracy: 0.0001)
        XCTAssertEqual(p.dragRange.lowerBound, p.list, accuracy: 0.0001)
        XCTAssertGreaterThan(p.detail, 600)        // detail can exceed the old cap
    }

    /// Both panes keep their minimums across a sweep of window widths.
    func test_split_minimumsAlwaysHeld() {
        for w in stride(from: 980.0, through: 2400.0, by: 37) {
            let p = PaneWidth.split(available: w, sidebar: 172, listFraction: 0.42)
            XCTAssertGreaterThanOrEqual(p.list, 240 - 0.0001, "w=\(w)")
            XCTAssertGreaterThanOrEqual(p.detail, 360 - 0.0001, "w=\(w)")
        }
    }

    /// A window too narrow to satisfy every minimum must not trap on an inverted
    /// range; the list keeps its floor and the drag range collapses to a point.
    func test_split_narrowWindow_noInvertedRange() {
        let p = PaneWidth.split(available: 600, sidebar: 150, listFraction: 0.42)
        XCTAssertLessThanOrEqual(p.dragRange.lowerBound, p.dragRange.upperBound)
        XCTAssertEqual(p.list, 240, accuracy: 0.0001)              // list floor
        XCTAssertGreaterThanOrEqual(p.detail, 0)
    }
}
