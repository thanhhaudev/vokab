import XCTest
@testable import VokabKit

final class ClozeBuilderTests: XCTestCase {
    func testBlanksWholeWordCaseInsensitive() {
        let p = ClozeBuilder.build(answer: "Decide", examples: ["We decide today"])
        XCTAssertEqual(p?.sentence, "We _____ today")
        XCTAssertEqual(p?.answer, "Decide")
    }
    func testDoesNotBlankSubstring() {
        XCTAssertNil(ClozeBuilder.build(answer: "cat", examples: ["A new category"]))
    }
    func testBlanksWholeWordWhenPresent() {
        let p = ClozeBuilder.build(answer: "cat", examples: ["A new category", "The cat sat"])
        XCTAssertEqual(p?.sentence, "The _____ sat")
    }
    func testBlanksPhrase() {
        let p = ClozeBuilder.build(answer: "look forward to", examples: ["I look forward to it"])
        XCTAssertEqual(p?.sentence, "I _____ it")
    }
    func testReturnsNilWhenNoExampleContainsAnswer() {
        XCTAssertNil(ClozeBuilder.build(answer: "zzz", examples: ["abc def"]))
    }
    func testReturnsNilForEmptyAnswerOrExamples() {
        XCTAssertNil(ClozeBuilder.build(answer: "  ", examples: ["anything"]))
        XCTAssertNil(ClozeBuilder.build(answer: "word", examples: []))
    }
    func testBlanksOnlyFirstOccurrence() {
        let p = ClozeBuilder.build(answer: "the", examples: ["the cat the dog"])
        XCTAssertEqual(p?.sentence, "_____ cat the dog")
    }
}
