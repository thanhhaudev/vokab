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

    // MARK: - Fix 2: lock doc claim — math/currency symbols survive, punctuation chars are stripped

    func testWordKeepsEdgeSymbols() {
        // $ + = < > are Unicode symbols (not punctuation) → survive at edges.
        XCTAssertEqual(InputCleaner.clean("$5", type: .word), "$5")
        XCTAssertEqual(InputCleaner.clean("<tag>", type: .word), "<tag>")   // < > survive
        XCTAssertEqual(InputCleaner.clean("c++", type: .word), "c++")
        XCTAssertEqual(InputCleaner.clean("=value=", type: .word), "=value=")
    }

    func testWordStripsEdgePunctuationSymbols() {
        // & # % @ / * are Unicode punctuation → stripped at edges.
        XCTAssertEqual(InputCleaner.clean("&amp", type: .word), "amp")
        XCTAssertEqual(InputCleaner.clean("#tag", type: .word), "tag")
        XCTAssertEqual(InputCleaner.clean("%20", type: .word), "20")
        XCTAssertEqual(InputCleaner.clean("@user", type: .word), "user")
        XCTAssertEqual(InputCleaner.clean("/path", type: .word), "path")
        XCTAssertEqual(InputCleaner.clean("*bold*", type: .word), "bold")
    }
}
