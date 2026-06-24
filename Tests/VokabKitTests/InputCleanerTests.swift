// Tests/VokabKitTests/InputCleanerTests.swift
import XCTest
@testable import VokabKit

final class InputCleanerTests: XCTestCase {

    func testWordStripsEdgePunctuationKeepsCaseAndInternal() {
        XCTAssertEqual(InputCleaner.clean("  \u{201C}Apple,\u{201D}  ", type: .word), "Apple")
        XCTAssertEqual(InputCleaner.clean("(run).", type: .word), "run")
        XCTAssertEqual(InputCleaner.clean("don't", type: .word), "don't")     // ' nội bộ giữ
        XCTAssertEqual(InputCleaner.clean("co-op;", type: .word), "co-op")    // - nội bộ giữ
        XCTAssertEqual(InputCleaner.clean("U.S.A.", type: .word), "U.S.A")    // mất dot cuối — chấp nhận
        XCTAssertEqual(InputCleaner.clean("e.g.,", type: .word), "e.g")
        XCTAssertEqual(InputCleaner.clean("\u{00BF}Hola!", type: .word), "Hola")
    }

    func testPhraseCollapsesInternalWhitespace() {
        XCTAssertEqual(InputCleaner.clean("\"kick   the\n bucket.\"", type: .phrase), "kick the bucket")
    }

    func testAllPunctuationBecomesEmpty() {
        XCTAssertEqual(InputCleaner.clean("...,", type: .word), "")
        XCTAssertEqual(InputCleaner.clean("  ??  ", type: .phrase), "")
    }

    func testParagraphKeepsPunctuationTrimsOnlyEdgeWhitespace() {
        XCTAssertEqual(InputCleaner.clean("  Hello, world!  ", type: .paragraphItem), "Hello, world!")
        XCTAssertEqual(InputCleaner.clean("\nA. B.\n", type: .paragraphItem), "A. B.")
    }

    func testCJKWordStripsIdeographicFullStop() {
        XCTAssertEqual(InputCleaner.clean("\u{732B}\u{3002}", type: .word), "\u{732B}") // 猫。 → 猫
    }
}
