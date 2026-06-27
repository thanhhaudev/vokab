import XCTest
@testable import VokabKit

final class ExampleMatchingTests: XCTestCase {

    func testNormalizationStripsTrailingPunctuationAndCase() {
        XCTAssertEqual(
            ExampleMatching.normalized("He looks forward to Friday."),
            ExampleMatching.normalized("he looks forward to friday"))
    }

    func testNormalizationCollapsesWhitespace() {
        XCTAssertEqual(
            ExampleMatching.normalized("We  look\tforward\nto it"),
            "we look forward to it")
    }

    func testNearDuplicateIsDetected() {
        let existing = ["He looks forward to Friday."]
        XCTAssertTrue(ExampleMatching.isDuplicate("he looks forward to friday", in: existing))
    }

    func testDistinctSentenceIsNotDuplicate() {
        let existing = ["He looks forward to Friday."]
        XCTAssertFalse(ExampleMatching.isDuplicate("She dreads Mondays.", in: existing))
    }

    func testBlankCandidateTreatedAsDuplicate() {
        XCTAssertTrue(ExampleMatching.isDuplicate("  .  ", in: []))
    }

    func testMergeAddsOnlyNewAndDedupesWithinBatch() {
        let existing = ["I look forward to seeing you."]
        let more = [
            "i look forward to seeing you",          // near-dup of existing
            "We look forward to the trip.",          // new
            "we look forward to the trip!"           // dup of the previous new one
        ]
        let merged = ExampleMatching.merge(existing, adding: more)
        XCTAssertEqual(merged, [
            "I look forward to seeing you.",
            "We look forward to the trip."
        ])
    }

    func testMergeUnchangedWhenAllDuplicates() {
        let existing = ["The roof spans the hall."]
        let merged = ExampleMatching.merge(existing, adding: ["the roof spans the hall"])
        XCTAssertEqual(merged, existing)
    }
}
