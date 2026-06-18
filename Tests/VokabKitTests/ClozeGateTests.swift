import XCTest
@testable import VokabKit

final class ClozeGateTests: XCTestCase {
    func testQualifiesAtThreshold() {
        XCTAssertTrue(ClozeGate.qualifies(interval: 3, reviewCount: 2, minInterval: 3, minReps: 2))
    }
    func testFailsBelowInterval() {
        XCTAssertFalse(ClozeGate.qualifies(interval: 2, reviewCount: 2, minInterval: 3, minReps: 2))
    }
    func testFailsBelowReps() {
        XCTAssertFalse(ClozeGate.qualifies(interval: 5, reviewCount: 1, minInterval: 3, minReps: 2))
    }
    func testQualifiesWellAbove() {
        XCTAssertTrue(ClozeGate.qualifies(interval: 7, reviewCount: 4, minInterval: 3, minReps: 2))
    }
}
