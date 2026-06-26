import XCTest
@testable import VokabKit

final class PhraseSpanMatcherTests: XCTestCase {
    func testAtomsSplitWordsAndSeparators() {
        let atoms = PhraseSpanMatcher.atoms("we ran out of time.")
        XCTAssertEqual(atoms.map(\.text),
                       ["we", " ", "ran", " ", "out", " ", "of", " ", "time", "."])
        XCTAssertEqual(atoms.filter(\.isWord).map(\.text),
                       ["we", "ran", "out", "of", "time"])
    }

    func testSpansMatchesContiguousPhrase() {
        let words = ["we", "ran", "out", "of", "time"]
        XCTAssertEqual(PhraseSpanMatcher.spans(words: words, phrases: ["run out of"]),
                       [1..<4])
    }

    func testSpansLenientInflection() {
        // "runs out of" should still match the base phrase "run out of".
        let words = ["she", "runs", "out", "of", "ideas"]
        XCTAssertEqual(PhraseSpanMatcher.spans(words: words, phrases: ["run out of"]),
                       [1..<4])
    }

    func testSpansPrefersLongerPhrase() {
        let words = ["ran", "out", "of"]
        let spans = PhraseSpanMatcher.spans(words: words, phrases: ["out of", "run out of"])
        XCTAssertEqual(spans, [0..<3])   // longer phrase wins, single span
    }

    func testSpansIgnoresSingleWordPhrasesAndNoMatch() {
        let words = ["a", "quick", "run"]
        XCTAssertEqual(PhraseSpanMatcher.spans(words: words, phrases: ["run"]), [])     // single-word ignored
        XCTAssertEqual(PhraseSpanMatcher.spans(words: words, phrases: ["go for"]), [])  // no match
    }
}
