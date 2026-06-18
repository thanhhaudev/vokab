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
        XCTAssertEqual(sel, [0, 1])             // skepticism (index 2) already saved → excluded
    }

    func testAllNewSelectsAll() {
        let items = [item("a"), item("b")]
        XCTAssertEqual(ParagraphSelection.defaultSelection(items: items, existingNormalized: []), [0, 1])
    }

    func testEmptyWordNotSelected() {
        let items = [item("")]
        XCTAssertTrue(ParagraphSelection.defaultSelection(items: items, existingNormalized: []).isEmpty)
    }
}
