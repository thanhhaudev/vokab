import XCTest
@testable import VokabKit

final class ParagraphSelectionTests: XCTestCase {
    private func item(_ w: String) -> ParagraphItem {
        try! JSONCleaning.decode(ParagraphItem.self, from: "{\"word\":\"\(w)\"}")
    }

    func testSelectsOnlyNewWords() {
        let items = [item("Exacerbate"), item("placate"), item("skepticism")]
        let existing: Set<String> = [TextKey.normalize("skepticism")]
        let sel = ParagraphSelection.defaultSelection(items: items, existingNormalized: existing)
        // Returns word keys, not indices: "skepticism" already saved → excluded
        XCTAssertEqual(sel, [TextKey.normalize("Exacerbate"), TextKey.normalize("placate")])
    }

    func testAllNewSelectsAll() {
        let items = [item("a"), item("b")]
        let sel = ParagraphSelection.defaultSelection(items: items, existingNormalized: [])
        XCTAssertEqual(sel, [TextKey.normalize("a"), TextKey.normalize("b")])
    }

    func testEmptyWordNotSelected() {
        let items = [item("")]
        XCTAssertTrue(ParagraphSelection.defaultSelection(items: items, existingNormalized: []).isEmpty)
    }
}
