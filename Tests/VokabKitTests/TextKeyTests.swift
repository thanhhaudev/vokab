import XCTest
@testable import VokabKit

final class TextKeyTests: XCTestCase {

    func testNormalizeStripsEdgePunctuationAndLowercases() {
        XCTAssertEqual(TextKey.normalize("Apple,"), "apple")
        XCTAssertEqual(TextKey.normalize("\u{201C}Apple\u{201D}"), "apple")
        XCTAssertEqual(TextKey.normalize("  RUN.  "), "run")
    }

    func testNormalizeKeepsInternalPunctuationAndCollapsesSpaces() {
        XCTAssertEqual(TextKey.normalize("co-op"), "co-op")
        XCTAssertEqual(TextKey.normalize("kick   the bucket."), "kick the bucket")
    }

    func testCacheKeyFoldsTextAndLanguage() {
        XCTAssertEqual(TextKey.cacheKey(text: "Apple,", language: "EN"), "apple::en")
    }
}
