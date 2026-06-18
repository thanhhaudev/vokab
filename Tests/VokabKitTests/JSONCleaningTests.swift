import XCTest
@testable import VokabKit

final class JSONCleaningTests: XCTestCase {
    func testPlainJSONUnchanged() {
        let input = #"{"a":1}"#
        XCTAssertEqual(JSONCleaning.stripJSONFences(input), #"{"a":1}"#)
    }

    func testStripsJSONFence() {
        let input = "```json\n{\"a\":1}\n```"
        XCTAssertEqual(JSONCleaning.stripJSONFences(input), #"{"a":1}"#)
    }

    func testStripsBareFence() {
        let input = "```\n{\"a\":1}\n```"
        XCTAssertEqual(JSONCleaning.stripJSONFences(input), #"{"a":1}"#)
    }

    func testTrimsWhitespace() {
        let input = "  \n {\"a\":1}\n  "
        XCTAssertEqual(JSONCleaning.stripJSONFences(input), #"{"a":1}"#)
    }

    func testStripsPreamble() {
        let input = "Here is your JSON:\n{\"a\":1}\nHope that helps!"
        XCTAssertEqual(JSONCleaning.stripJSONFences(input), #"{"a":1}"#)
    }

    func testHandlesArrayPayload() {
        let input = "```json\n[{\"word\":\"x\"}]\n```"
        XCTAssertEqual(JSONCleaning.stripJSONFences(input), #"[{"word":"x"}]"#)
    }
}
