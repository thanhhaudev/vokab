import XCTest
@testable import VokabKit

final class AgyActivityTests: XCTestCase {

    /// Thread-safe recorder for the in-flight counts reported by AgyActivity.
    private final class Recorder: @unchecked Sendable {
        private let lock = NSLock()
        private var values: [Int] = []
        func record(_ v: Int) { lock.lock(); values.append(v); lock.unlock() }
        var all: [Int] { lock.lock(); defer { lock.unlock() }; return values }
        var max: Int { all.max() ?? 0 }
        var last: Int { all.last ?? -1 }
    }

    func test_beginEnd_reportsCounts_andNeverGoesNegative() {
        let activity = AgyActivity()
        let rec = Recorder()
        activity.setOnChange { rec.record($0) }

        activity.begin()   // 1
        activity.begin()   // 2
        activity.end()     // 1
        activity.end()     // 0
        activity.end()     // clamped at 0

        XCTAssertEqual(rec.all, [1, 2, 1, 0, 0])
    }

    /// Every AgyService call must bracket itself: the in-flight count rises to 1
    /// while running and returns to 0 when done — this is what lights/clears the
    /// menubar activity dot for ALL background AI work.
    func test_agyService_bracketsEachCall() async throws {
        let activity = AgyActivity()
        let rec = Recorder()
        activity.setOnChange { rec.record($0) }
        let runner = MockAgyRunner(response: #"{"pos":"noun","meaning_vi":"x"}"#)
        let service = AgyService(runner: runner, settings: VokabSettings(), activity: activity)

        _ = try await service.defineWord("ephemeral", language: "en")

        XCTAssertEqual(rec.max, 1, "call should go in-flight")
        XCTAssertEqual(rec.last, 0, "count should return to idle after the call")
    }
}
