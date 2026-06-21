import XCTest
@testable import VokabKit

final class ParagraphChunkerTests: XCTestCase {
    func testShortTextIsSingleChunk() {
        let text = "One small sentence here."
        XCTAssertEqual(ParagraphChunker.chunk(text, maxWords: 120), [text])
    }

    func testBlankTextYieldsNoChunks() {
        XCTAssertTrue(ParagraphChunker.chunk("   \n  ", maxWords: 120).isEmpty)
    }

    func testGroupsSentencesUpToMaxWords() {
        // Three 4-word sentences; maxWords 8 → [s1+s2], [s3].
        let s1 = "Alpha beta gamma delta. "
        let s2 = "Epsilon zeta eta theta. "
        let s3 = "Iota kappa lambda mu."
        let chunks = ParagraphChunker.chunk(s1 + s2 + s3, maxWords: 8)
        XCTAssertEqual(chunks.count, 2)
        XCTAssertTrue(chunks[0].contains("Alpha") && chunks[0].contains("Epsilon"))
        XCTAssertTrue(chunks[1].contains("Iota"))
    }

    func testOverlongSentenceBecomesOwnChunk() {
        // One 6-word sentence with maxWords 3 → kept whole as its own chunk.
        let chunks = ParagraphChunker.chunk("one two three four five six.", maxWords: 3)
        XCTAssertEqual(chunks.count, 1)
        XCTAssertEqual(chunks[0].trimmingCharacters(in: .whitespacesAndNewlines),
                       "one two three four five six.")
    }

    func testWordCountAcrossChunksIsPreserved() {
        let text = "a b c. d e f. g h i. j k l."   // 4 sentences × 3 words = 12 words
        let chunks = ParagraphChunker.chunk(text, maxWords: 6)
        let total = chunks.joined().split { $0 == " " || $0 == "." }.filter { !$0.isEmpty }.count
        XCTAssertEqual(total, 12)
    }
}
