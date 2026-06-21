// Tests/VokabKitTests/ParagraphMergeTests.swift
import XCTest
@testable import VokabKit

final class ParagraphMergeTests: XCTestCase {
    private func item(_ w: String, _ cefr: String? = nil) -> ParagraphItem {
        let json = cefr.map { #"{"word":"\#(w)","cefr":"\#($0)"}"# } ?? #"{"word":"\#(w)"}"#
        return try! JSONCleaning.decode(ParagraphItem.self, from: json)
    }

    func testAppendsOnlyNewWords() {
        let existing = [item("resilient"), item("albeit")]
        let incoming = [item("albeit"), item("however"), item("grasp")]
        let merged = ParagraphMerge.union(existing, incoming)
        XCTAssertEqual(merged.map { $0.word }, ["resilient", "albeit", "however", "grasp"])
    }

    func testExistingWinsOnConflict() {
        let existing = [item("grasp", "B1")]
        let incoming = [item("grasp", "C2")]            // same word, different data
        let merged = ParagraphMerge.union(existing, incoming)
        XCTAssertEqual(merged.count, 1)
        XCTAssertEqual(merged[0].cefr, "B1")            // existing data preserved
    }

    func testDedupesCaseAndWhitespaceInsensitively() {
        let merged = ParagraphMerge.union([item("Grasp")], [item("  grasp ")])
        XCTAssertEqual(merged.count, 1)
    }

    func testDropsEmptyWords() {
        let merged = ParagraphMerge.union([], [item(""), item("real")])
        XCTAssertEqual(merged.map { $0.word }, ["real"])
    }
}
