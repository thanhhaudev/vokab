import XCTest
@testable import VokabKit

final class InputClassifierTests: XCTestCase {
    func testSingleTokenIsWord() {
        XCTAssertEqual(InputClassifier.classify("ephemeral"), .word)
        XCTAssertEqual(InputClassifier.classify("  serendipity  "), .word)
    }

    func testShortPhrase() {
        XCTAssertEqual(InputClassifier.classify("give up on"), .phrase)
        XCTAssertEqual(InputClassifier.classify("kick the bucket"), .phrase)
    }

    func testTrailingPunctuationStillPhrase() {
        XCTAssertEqual(InputClassifier.classify("give up."), .phrase)
    }

    func testLongRunIsParagraph() {
        XCTAssertEqual(InputClassifier.classify("one two three four five six seven"), .paragraphItem)
    }

    func testMultiSentenceIsParagraph() {
        let text = "The cat sat. The dog ran away quickly."
        XCTAssertEqual(InputClassifier.classify(text), .paragraphItem)
    }

    // Languages without spaces must not collapse a whole sentence into one "word".
    func testJapaneseSentenceIsParagraph() {
        let text = "発注データの「備考」欄に含まれるキーワードに基づいて、納品場所を自動的に割り当てます。"
        XCTAssertEqual(InputClassifier.classify(text), .paragraphItem)
    }

    func testJapaneseSingleWordIsWord() {
        XCTAssertEqual(InputClassifier.classify("猫"), .word)
        XCTAssertEqual(InputClassifier.classify("ありがとう"), .word)
    }

    func testChineseMultiSentenceIsParagraph() {
        XCTAssertEqual(InputClassifier.classify("这是第一句。这是第二句。"), .paragraphItem)
    }
}
