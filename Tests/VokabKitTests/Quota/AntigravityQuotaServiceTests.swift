import XCTest
@testable import VokabKit

final class AntigravityQuotaServiceTests: XCTestCase {
    private func sampleSummary(at t: Date) -> AntigravityQuotaSummary {
        AntigravityQuotaSummary(fetchedAt: t, groups: [
            .init(displayName: "Gemini Models", description: nil, buckets: [
                .init(bucketId: "gemini-5h", displayName: nil, window: .fiveHour, remainingFraction: 0.9, resetTime: nil)])
        ])
    }
    func test_usesDetectedServer_whenRunning() async throws {
        let clock = ClockBox(Date(timeIntervalSince1970: 1000))
        var fetchCount = 0
        let svc = AntigravityQuotaService(
            detect: { AntigravityProcessInfo(pid: 1, csrfToken: "c", listeningPorts: [5000]) },
            fetch: { _, _ in fetchCount += 1; return self.sampleSummary(at: clock.now()) },
            spawnFetch: { XCTFail("should not spawn when detected"); throw AntigravityQuotaError.transient },
            now: clock.now)
        let s = await svc.summary()
        XCTAssertEqual(s?.groups.first?.key, "gemini")
        XCTAssertEqual(fetchCount, 1)
    }
    func test_spawns_whenNoServerDetected() async throws {
        let clock = ClockBox(Date(timeIntervalSince1970: 1000))
        var spawned = 0
        let svc = AntigravityQuotaService(
            detect: { nil },
            fetch: { _, _ in XCTFail("no detected server"); throw AntigravityQuotaError.transient },
            spawnFetch: { spawned += 1; return self.sampleSummary(at: clock.now()) },
            now: clock.now)
        _ = await svc.summary()
        XCTAssertEqual(spawned, 1)
    }
    func test_cachesWithin60s() async throws {
        let clock = ClockBox(Date(timeIntervalSince1970: 1000))
        var fetchCount = 0
        let svc = AntigravityQuotaService(
            detect: { AntigravityProcessInfo(pid: 1, csrfToken: "c", listeningPorts: [5000]) },
            fetch: { _, _ in fetchCount += 1; return self.sampleSummary(at: clock.now()) },
            spawnFetch: { throw AntigravityQuotaError.transient }, now: clock.now)
        _ = await svc.summary()
        clock.advance(30)
        _ = await svc.summary()
        XCTAssertEqual(fetchCount, 1)
        clock.advance(40)
        _ = await svc.summary()
        XCTAssertEqual(fetchCount, 2)
    }
    func test_returnsNil_whenUnavailable() async throws {
        let svc = AntigravityQuotaService(detect: { nil },
            fetch: { _, _ in throw AntigravityQuotaError.transient },
            spawnFetch: { throw LanguageServerLauncher.LaunchError.binaryMissing },
            now: { Date(timeIntervalSince1970: 1000) })
        let s = await svc.summary()
        XCTAssertNil(s)
    }
    func test_refresh_cooldownFloor_blocksRapidReload() async throws {
        let clock = ClockBox(Date(timeIntervalSince1970: 1000))
        var fetchCount = 0
        let svc = AntigravityQuotaService(
            detect: { AntigravityProcessInfo(pid: 1, csrfToken: "c", listeningPorts: [5000]) },
            fetch: { _, _ in fetchCount += 1; return self.sampleSummary(at: clock.now()) },
            spawnFetch: { throw AntigravityQuotaError.transient },
            now: clock.now, minRefreshInterval: 10)
        if case .refreshed = await svc.refresh() {} else { XCTFail("first refresh should fetch") }
        XCTAssertEqual(fetchCount, 1)
        clock.advance(5)
        if case let .tooSoon(retryAfter) = await svc.refresh() {
            XCTAssertEqual(retryAfter, 5, accuracy: 0.01)
        } else { XCTFail("expected tooSoon") }
        XCTAssertEqual(fetchCount, 1)
        clock.advance(6)
        if case .refreshed = await svc.refresh() {} else { XCTFail("should fetch after floor") }
        XCTAssertEqual(fetchCount, 2)
    }
}

final class ClockBox: @unchecked Sendable {
    private var t: Date; private let lock = NSLock()
    init(_ t: Date) { self.t = t }
    func now() -> Date { lock.lock(); defer { lock.unlock() }; return t }
    func advance(_ s: TimeInterval) { lock.lock(); t = t.addingTimeInterval(s); lock.unlock() }
}
