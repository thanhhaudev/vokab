import XCTest
@testable import VokabKit

final class CategoryNameTests: XCTestCase {
    func test_snakeCase_toTitleish() {
        XCTAssertEqual(CategoryName.prettify("social_media"), "Social media")
    }
    func test_kebabCase_toTitleish() {
        XCTAssertEqual(CategoryName.prettify("daily-life"), "Daily life")
    }
    func test_alreadyHuman_isPreserved() {
        XCTAssertEqual(CategoryName.prettify("Technology"), "Technology")
        XCTAssertEqual(CategoryName.prettify("Arts & Culture"), "Arts & Culture")
    }
    func test_trimsAndCollapsesSpaces() {
        XCTAssertEqual(CategoryName.prettify("  news__politics "), "News politics")
    }
    func test_empty_isEmpty() {
        XCTAssertEqual(CategoryName.prettify(""), "")
        XCTAssertEqual(CategoryName.prettify("   "), "")
    }
}
