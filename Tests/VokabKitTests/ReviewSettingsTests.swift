import XCTest
@testable import VokabKit

final class ReviewSettingsTests: XCTestCase {
    func testUnlockHonorsThresholds() {
        XCTAssertTrue(ProductionGate.qualifies(interval: 7, reviewCount: 2, minInterval: 7, minReps: 2))
        XCTAssertFalse(ProductionGate.qualifies(interval: 6, reviewCount: 5, minInterval: 7, minReps: 2))
        XCTAssertFalse(ProductionGate.qualifies(interval: 30, reviewCount: 1, minInterval: 7, minReps: 2))
        // Custom thresholds.
        XCTAssertTrue(ProductionGate.qualifies(interval: 3, reviewCount: 1, minInterval: 3, minReps: 1))
    }

    func testNewCardLimitKeepsReviews() {
        let cards = [true, false, true, true, false]   // true == new
        let out = NewCardLimit.apply(cards, isNew: { $0 }, limit: 2)
        XCTAssertEqual(out.count, 4)                    // 2 new + 2 reviews
        XCTAssertEqual(out.filter { $0 }.count, 2)      // only 2 new kept
        XCTAssertEqual(out.filter { !$0 }.count, 2)     // all reviews kept
    }

    func testNewCardLimitZeroDropsAllNew() {
        let cards = [true, false, true]
        let out = NewCardLimit.apply(cards, isNew: { $0 }, limit: 0)
        XCTAssertEqual(out, [false])
    }
}
