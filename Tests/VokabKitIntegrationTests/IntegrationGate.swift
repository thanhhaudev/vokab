import XCTest
@testable import VokabKit

/// Real-`agy` contract tests. These hit the live `agy` CLI and assert JSON
/// structure (not content). They are skipped unless `VOKAB_AGY_INTEGRATION=1`
/// so that offline CI and other contributors are not blocked by agy/auth.
enum IntegrationGate {
    static var enabled: Bool {
        ProcessInfo.processInfo.environment["VOKAB_AGY_INTEGRATION"] == "1"
    }

    /// Calls `XCTSkip` when integration tests are disabled.
    static func skipUnlessEnabled() throws {
        try XCTSkipUnless(enabled, "Set VOKAB_AGY_INTEGRATION=1 to run real-agy tests")
    }
}

final class IntegrationGateTests: XCTestCase {
    func testGateReflectsEnvironment() {
        // Always-true sanity check so the target has at least one runnable test.
        XCTAssertEqual(IntegrationGate.enabled,
                       ProcessInfo.processInfo.environment["VOKAB_AGY_INTEGRATION"] == "1")
    }
}
