import XCTest
@testable import VokabKit

final class ParagraphHighlighterTests: XCTestCase {

    func testExactMatchHighlights() {
        let segs = ParagraphHighlighter.segments(source: "Met with skepticism today.",
                                                 candidates: ["skepticism"])
        XCTAssertTrue(segs.contains { $0.text == "skepticism" && $0.isHighlight })
        XCTAssertFalse(segs.contains { $0.text == "today" && $0.isHighlight })
    }

    func testInflectionPrefixHighlights() {
        let segs = ParagraphHighlighter.segments(source: "It exacerbated the issue.",
                                                 candidates: ["exacerbate"])
        XCTAssertTrue(segs.contains { $0.text == "exacerbated" && $0.isHighlight })
    }

    func testCaseInsensitive() {
        let segs = ParagraphHighlighter.segments(source: "VENEER was thin.",
                                                 candidates: ["veneer"])
        XCTAssertTrue(segs.contains { $0.text == "VENEER" && $0.isHighlight })
    }

    func testShortWordsOnlyExactMatch() {
        // "to" (len 2) must not prefix-match "today"; only its exact occurrence.
        let segs = ParagraphHighlighter.segments(source: "today we go to school",
                                                 candidates: ["to"])
        XCTAssertFalse(segs.contains { $0.text == "today" && $0.isHighlight })
        XCTAssertTrue(segs.contains { $0.text == "to" && $0.isHighlight })
    }

    func testReconstructsOriginalSource() {
        let source = "The committee's decision—met with skepticism."
        let segs = ParagraphHighlighter.segments(source: source, candidates: ["skepticism"])
        XCTAssertEqual(segs.map(\.text).joined(), source)   // lossless segmentation
    }
}
