import XCTest
@testable import VokabKit

final class LanguageDetectorTests: XCTestCase {
    func test_singleEnglishWord_returnsEN() {
        XCTAssertEqual(LanguageDetector.detect("stubborn", default: "en"), "en")
        XCTAssertEqual(LanguageDetector.detect("stubbon", default: "en"), "en")  // typo vẫn ASCII → en
    }
    func test_vietnameseWithDiacritics_returnsVI() {
        XCTAssertEqual(LanguageDetector.detect("bướng bỉnh", default: "en"), "vi")
        XCTAssertEqual(LanguageDetector.detect("Tôi rất thích học", default: "en"), "vi")
    }
    func test_empty_returnsDefault() {
        XCTAssertEqual(LanguageDetector.detect("   ", default: "vi"), "vi")
    }
    func test_hasVietnameseDiacritics_pure() {
        XCTAssertTrue(LanguageDetector.hasVietnameseDiacritics("đặc biệt"))
        XCTAssertFalse(LanguageDetector.hasVietnameseDiacritics("special"))
    }
    func test_isPlainASCIILetters_pure() {
        XCTAssertTrue(LanguageDetector.isPlainASCIILetters("Stubborn"))
        XCTAssertFalse(LanguageDetector.isPlainASCIILetters("café"))
        XCTAssertFalse(LanguageDetector.isPlainASCIILetters("123"))
    }
}
