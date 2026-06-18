import XCTest
@testable import VokabKit

final class SM2Tests: XCTestCase {

    private func fresh() -> ReviewState {
        ReviewState(entryId: 1, easeFactor: 2.5, interval: 0, dueDate: Date(), reviewCount: 0)
    }

    func testFirstGoodIntervalIsOne() {
        let p = SM2.project(easeFactor: 2.5, interval: 0, reviewCount: 0, grade: .good)
        XCTAssertEqual(p.interval, 1)
        XCTAssertEqual(p.reviewCount, 1)
        XCTAssertEqual(p.easeFactor, 2.5, accuracy: 0.0001)   // good leaves EF unchanged
    }

    func testSecondGoodIntervalIsSix() {
        let p = SM2.project(easeFactor: 2.5, interval: 1, reviewCount: 1, grade: .good)
        XCTAssertEqual(p.interval, 6)
        XCTAssertEqual(p.reviewCount, 2)
    }

    func testThirdGoodIsRoundedProduct() {
        // interval 6, EF 2.5 → 15
        let p = SM2.project(easeFactor: 2.5, interval: 6, reviewCount: 2, grade: .good)
        XCTAssertEqual(p.interval, 15)
        XCTAssertEqual(p.reviewCount, 3)
    }

    func testAgainResetsAndLowersEF() {
        let p = SM2.project(easeFactor: 2.5, interval: 15, reviewCount: 3, grade: .again)
        XCTAssertEqual(p.interval, 0)
        XCTAssertEqual(p.reviewCount, 0)
        XCTAssertLessThan(p.easeFactor, 2.5)
    }

    func testEaseFactorFloor() {
        var ef = 1.3
        for _ in 0..<10 {
            ef = SM2.project(easeFactor: ef, interval: 5, reviewCount: 3, grade: .again).easeFactor
        }
        XCTAssertGreaterThanOrEqual(ef, 1.3)
    }

    func testEasyRaisesEF() {
        let p = SM2.project(easeFactor: 2.5, interval: 6, reviewCount: 2, grade: .easy)
        XCTAssertGreaterThan(p.easeFactor, 2.5)
    }

    func testScheduleSetsDueDateByInterval() throws {
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let cal = Calendar(identifier: .gregorian)
        let updated = SM2.schedule(fresh(), grade: .good, now: now, calendar: cal)
        let expected = cal.date(byAdding: .day, value: 1, to: now)!
        XCTAssertEqual(updated.dueDate.timeIntervalSince1970, expected.timeIntervalSince1970, accuracy: 1)
        let lastReview = try XCTUnwrap(updated.lastReview)
        XCTAssertEqual(lastReview.timeIntervalSince1970, now.timeIntervalSince1970, accuracy: 1)
    }

    func testIntervalPreviewCoversAllGrades() {
        let preview = SM2.intervalPreview(fresh())
        XCTAssertEqual(preview.count, 4)
        XCTAssertEqual(preview[.again], 0)
        XCTAssertEqual(preview[.good], 1)
    }
}
