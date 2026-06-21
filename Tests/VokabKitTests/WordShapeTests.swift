import XCTest
@testable import VokabKit

final class WordShapeTests: XCTestCase {
    func testGibberishIsFlagged() {
        for w in ["asdfgh", "qwerty", "bcdfg", "aaaaa", "zzzzzz", "lkjhgf"] {
            XCTAssertTrue(WordShape.looksLikeGibberish(w), "\(w) should be gibberish")
        }
    }

    func testRealOrPlausibleWordsAreNotFlagged() {
        // Proper nouns / technical terms NSSpellChecker may not suggest for must NOT be red-flagged.
        for w in ["receive", "cat", "API", "Nginx", "Hà", "ok", "go"] {
            XCTAssertFalse(WordShape.looksLikeGibberish(w), "\(w) should not be gibberish")
        }
    }
}
