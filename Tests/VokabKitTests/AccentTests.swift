import XCTest
@testable import VokabKit

final class AccentTests: XCTestCase {
    func testBCP47Mapping() {
        XCTAssertEqual(Accent.us.bcp47, "en-US")
        XCTAssertEqual(Accent.uk.bcp47, "en-GB")
    }

    func testInitFromSettingsValue() {
        XCTAssertEqual(Accent(settingsValue: "en-US"), .us)
        XCTAssertEqual(Accent(settingsValue: "en-GB"), .uk)
    }

    func testUnknownSettingsValueFallsBackToUS() {
        XCTAssertEqual(Accent(settingsValue: "xx-YY"), .us)
        XCTAssertEqual(Accent(settingsValue: ""), .us)
    }
}
