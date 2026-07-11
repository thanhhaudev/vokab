import XCTest
@testable import VokabKit

final class ListeningFrontTests: XCTestCase {
    // Helper with the shipped defaults (minInterval 1, minReps 2).
    private func decide(interval: Int, reviewCount: Int, enabled: Bool = true) -> Bool {
        ListeningFront.shouldUseAudioFront(
            interval: interval, reviewCount: reviewCount,
            enabled: enabled, minInterval: 1, minReps: 2)
    }

    func testDisabledNeverUsesAudioFront() {
        XCTAssertFalse(decide(interval: 10, reviewCount: 4, enabled: false))
    }
    func testBelowIntervalStaysText() {
        XCTAssertFalse(decide(interval: 0, reviewCount: 2))   // interval < 1
    }
    func testBelowRepsStaysText() {
        XCTAssertFalse(decide(interval: 5, reviewCount: 1))   // reps < 2, and odd
        XCTAssertFalse(decide(interval: 5, reviewCount: 0))   // reps < 2, even → still gated by maturity
    }
    func testMaturedEvenReviewCountUsesAudioFront() {
        XCTAssertTrue(decide(interval: 1, reviewCount: 2))    // at threshold, even
        XCTAssertTrue(decide(interval: 9, reviewCount: 4))    // well above, even
    }
    func testMaturedOddReviewCountStaysText() {
        XCTAssertFalse(decide(interval: 9, reviewCount: 3))   // matured but odd → alternate to text
    }
    func testCustomThresholdsRespected() {
        // reps threshold 4: reviewCount 2 (even) is below → text.
        XCTAssertFalse(ListeningFront.shouldUseAudioFront(
            interval: 9, reviewCount: 2, enabled: true, minInterval: 1, minReps: 4))
    }
}
