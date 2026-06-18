import XCTest
@testable import VokabKit

final class QuotaWarningTests: XCTestCase {
    func test_severity_thresholds() {
        XCTAssertEqual(QuotaSeverity.forRemaining(0.9), .ok)
        XCTAssertEqual(QuotaSeverity.forRemaining(0.18), .amber)
        XCTAssertEqual(QuotaSeverity.forRemaining(0.04), .red)
        XCTAssertEqual(QuotaSeverity.forRemaining(0.0), .red)
    }
    func test_severity_nilRemaining_isOk() {
        XCTAssertEqual(QuotaSeverity.forRemaining(nil), .ok)
    }
    func test_redNotificationGate_firesOnceUntilRecovered() {
        var gate = RedNotificationGate()
        XCTAssertTrue(gate.shouldNotify(severity: .red))
        XCTAssertFalse(gate.shouldNotify(severity: .red))
        XCTAssertFalse(gate.shouldNotify(severity: .amber))
        XCTAssertTrue(gate.shouldNotify(severity: .red))
    }
}
