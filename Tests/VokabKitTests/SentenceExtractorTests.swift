import XCTest
@testable import VokabKit

final class SentenceExtractorTests: XCTestCase {
    func testPicksContainingSentence() {
        let src = "I went home early. The deadline will exacerbate the stress. We left."
        XCTAssertEqual(SentenceExtractor.extractSentence(containing: "exacerbate", from: src),
                       "The deadline will exacerbate the stress.")
    }

    func testMatchesInflectedForm() {
        let src = "The crisis exacerbated tensions across the region."
        XCTAssertEqual(SentenceExtractor.extractSentence(containing: "exacerbate", from: src),
                       "The crisis exacerbated tensions across the region.")
    }

    func testReturnsNilWhenAbsent() {
        XCTAssertNil(SentenceExtractor.extractSentence(containing: "ubiquitous",
                                                       from: "A short plain sentence."))
    }

    func testReturnsNilWhenSourceIsJustTheTerm() {
        XCTAssertNil(SentenceExtractor.extractSentence(containing: "serendipity", from: "serendipity"))
    }

    func testTrimsWhitespaceAndSplitsOnNewline() {
        let src = "First line.\n   We embraced the serendipity of it.   \nLast."
        XCTAssertEqual(SentenceExtractor.extractSentence(containing: "serendipity", from: src),
                       "We embraced the serendipity of it.")
    }

    func testMultiWordPhraseUsesSubstring() {
        let src = "She said she was looking forward to the trip. Then she left."
        XCTAssertEqual(SentenceExtractor.extractSentence(containing: "looking forward to", from: src),
                       "She said she was looking forward to the trip.")
    }
}
