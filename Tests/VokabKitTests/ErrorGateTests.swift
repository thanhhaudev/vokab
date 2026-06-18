import XCTest
@testable import VokabKit
final class ErrorGateTests: XCTestCase {
    func testQualifiesAtThreshold() { XCTAssertTrue(ErrorGate.qualifies(interval: 5, reviewCount: 2, minInterval: 5, minReps: 2)) }
    func testFailsBelowInterval() { XCTAssertFalse(ErrorGate.qualifies(interval: 4, reviewCount: 2, minInterval: 5, minReps: 2)) }
    func testFailsBelowReps() { XCTAssertFalse(ErrorGate.qualifies(interval: 9, reviewCount: 1, minInterval: 5, minReps: 2)) }
}
