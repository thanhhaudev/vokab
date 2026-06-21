// Tests/VokabKitTests/ParagraphFilterTests.swift
import XCTest
@testable import VokabKit

final class ParagraphFilterTests: XCTestCase {
    private func item(_ w: String, _ cefr: String?) -> ParagraphItem {
        let json = cefr.map { #"{"word":"\#(w)","cefr":"\#($0)"}"# } ?? #"{"word":"\#(w)"}"#
        return try! JSONCleaning.decode(ParagraphItem.self, from: json)
    }

    func testKeepsAtOrAboveLevel() {
        let items = [item("a", "A2"), item("b", "B1"), item("c", "C1")]
        let kept = ParagraphFilter.atOrAbove(items, minLevel: .b1)
        XCTAssertEqual(kept.map { $0.word }, ["b", "c"])
    }

    func testNilCefrAlwaysKept() {
        let items = [item("a", "A1"), item("b", nil)]
        let kept = ParagraphFilter.atOrAbove(items, minLevel: .c2)
        XCTAssertEqual(kept.map { $0.word }, ["b"])   // a1 dropped, nil kept
    }

    func testUnparseableCefrKept() {
        let items = [item("a", "zz")]
        XCTAssertEqual(ParagraphFilter.atOrAbove(items, minLevel: .c1).count, 1)
    }
}
