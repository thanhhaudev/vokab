import XCTest
import GRDB
@testable import VokabKit

final class DashboardDataTests: XCTestCase {

    private func makeEntry(_ text: String) -> Entry {
        Entry(rawText: text, type: CardType.word.rawValue, language: "en",
              capturedAt: Date(timeIntervalSince1970: 1_700_000_000),
              aiResult: #"{"pos":"noun"}"#, cefr: "b2")
    }

    // MARK: count(on:)

    func testCountOnReturnsTodaysTallyAndZeroOtherwise() throws {
        let q = try VokabDatabase.makeInMemory()
        let log = ReviewLogRepository(dbQueue: q)
        let today = Date()
        try log.record(on: today)
        try log.record(on: today)

        XCTAssertEqual(try log.count(on: today), 2)

        let otherDay = Calendar.current.date(byAdding: .day, value: -3, to: today)!
        XCTAssertEqual(try log.count(on: otherDay), 0)
    }

    // MARK: dailyCounts(from:to:)

    func testDailyCountsReturnsBothRecordedDaysInRange() throws {
        let q = try VokabDatabase.makeInMemory()
        let log = ReviewLogRepository(dbQueue: q)
        let cal = Calendar.current
        let today = cal.startOfDay(for: Date())
        let yesterday = cal.date(byAdding: .day, value: -1, to: today)!

        try log.record(on: yesterday)
        try log.record(on: today)
        try log.record(on: today)

        let counts = try log.dailyCounts(from: yesterday, to: today)
        XCTAssertEqual(counts[TextKey.dayString(yesterday)], 1)
        XCTAssertEqual(counts[TextKey.dayString(today)], 2)
        XCTAssertEqual(counts.count, 2)
    }

    func testDailyCountsOrdersBounds() throws {
        let q = try VokabDatabase.makeInMemory()
        let log = ReviewLogRepository(dbQueue: q)
        let cal = Calendar.current
        let today = cal.startOfDay(for: Date())
        let yesterday = cal.date(byAdding: .day, value: -1, to: today)!
        try log.record(on: yesterday)
        try log.record(on: today)

        // bounds passed reversed should still work
        let counts = try log.dailyCounts(from: today, to: yesterday)
        XCTAssertEqual(counts.count, 2)
    }

    // MARK: dueForecast(days:)

    func testDueForecastBucketsByOffset() throws {
        let q = try VokabDatabase.makeInMemory()
        let entries = EntryRepository(dbQueue: q)
        let review = ReviewRepository(dbQueue: q)
        let cal = Calendar.current
        let now = Date()
        let today = cal.startOfDay(for: now)

        // due today (noon today, still bucket 0)
        let dueToday = cal.date(byAdding: .hour, value: 12, to: today)!
        // due in 3 days
        let dueIn3 = cal.date(byAdding: .day, value: 3, to: today)!
        // overdue (folds into bucket 0)
        let overdue = cal.date(byAdding: .day, value: -2, to: today)!

        _ = try entries.insertCapture(makeEntry("today"), dueDate: dueToday)
        _ = try entries.insertCapture(makeEntry("in3"), dueDate: dueIn3)
        _ = try entries.insertCapture(makeEntry("overdue"), dueDate: overdue)

        let forecast = try review.dueForecast(days: 7, asOf: now)
        XCTAssertEqual(forecast[0], 2)   // due-today + overdue
        XCTAssertEqual(forecast[3], 1)   // due-in-3
        XCTAssertNil(forecast[1])
    }

    func testDueForecastDropsBeyondHorizon() throws {
        let q = try VokabDatabase.makeInMemory()
        let entries = EntryRepository(dbQueue: q)
        let review = ReviewRepository(dbQueue: q)
        let cal = Calendar.current
        let now = Date()
        let today = cal.startOfDay(for: now)
        let dueFar = cal.date(byAdding: .day, value: 30, to: today)!

        _ = try entries.insertCapture(makeEntry("far"), dueDate: dueFar)

        let forecast = try review.dueForecast(days: 7, asOf: now)
        XCTAssertTrue(forecast.isEmpty)
    }
}
