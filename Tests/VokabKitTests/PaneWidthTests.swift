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
}
