import XCTest
@testable import VokabKit

/// agy reports `--print-timeout` overruns (and other failures) as `Error: ...`
/// on stdout with a zero exit code. `AgyClient.validate` must turn those into
/// real errors instead of letting them reach the JSON decoder.
final class AgyClientValidateTests: XCTestCase {

    func testValidJSONPassesThrough() throws {
        XCTAssertEqual(try AgyClient.validate(stdout: #"{"ok":true}"#), #"{"ok":true}"#)
        XCTAssertEqual(try AgyClient.validate(stdout: "  {\"a\":1}  "), "  {\"a\":1}  ")
    }

    func testTimedOutBecomesTimeoutError() {
        for output in ["Error: timed out waiting for response",
                       "error: timed out",
                       "Something: timed out waiting for response"] {
            XCTAssertThrowsError(try AgyClient.validate(stdout: output)) { error in
                XCTAssertEqual(error as? AgyError, .timeout, "for output: \(output)")
            }
        }
    }

    func testBareErrorBecomesNonZeroExit() {
        XCTAssertThrowsError(try AgyClient.validate(stdout: "Error: authentication required")) { error in
            guard case AgyError.nonZeroExit(let code, _) = error else {
                return XCTFail("expected nonZeroExit, got \(error)")
            }
            XCTAssertEqual(code, 0)
        }
    }

    func testErrorWordInsideValidJSONIsNotMisread() throws {
        // "Error" appearing inside a JSON payload must not trip the guard.
        let json = #"{"meaning_en":"Error message handling","pos":"noun"}"#
        XCTAssertEqual(try AgyClient.validate(stdout: json), json)
    }
}
