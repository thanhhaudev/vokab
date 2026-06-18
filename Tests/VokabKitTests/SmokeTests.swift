import XCTest
@testable import VokabKit

final class SmokeTests: XCTestCase {
    func testVersion() {
        XCTAssertEqual(VokabKit.version, "0.0.1")
    }
}
