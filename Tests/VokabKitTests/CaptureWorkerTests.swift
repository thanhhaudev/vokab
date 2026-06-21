import XCTest
@testable import VokabKit

final class CaptureWorkerTests: XCTestCase {
    func test_enqueue_runsAnalysis_andFiresOnChange() async throws {
        let queue = try VokabDatabase.makeInMemory()
        let entries = EntryRepository(dbQueue: queue)
        let cache = CacheRepository(dbQueue: queue)
        let quota = QuotaRepository(dbQueue: queue)
        let categories = CategoryService(dbQueue: queue)
        let settings = VokabSettings()
        let runner = MockAgyRunner(response: #"{"pos":"adjective","cefr_level":"B2"}"#)
        let agy = AgyService(runner: runner, settings: settings)
        let capture = CaptureService(agy: agy, entries: entries, cache: cache, quota: quota,
                                     categories: categories, settings: settings)

        let src = SourceContext(appName: "t", url: nil, capturedAt: Date())
        guard case let .pending(id, _) = try capture.beginCapture(text: "stubborn", language: "en", source: src)
        else { return XCTFail("expected .pending") }

        let changed = ChangeCounter()
        let worker = CaptureWorker(capture: capture, maxConcurrent: 2, onChange: { changed.bump() })
        await worker.enqueueAnalysis(entryId: id)
        await worker.drain()
        XCTAssertEqual(try entries.entry(id: id)?.analysisState, AnalysisState.ready.rawValue)
        XCTAssertGreaterThanOrEqual(changed.value, 1)
    }

    func test_onActivity_reportsInflightCount_risesThenReturnsToZero() async throws {
        let queue = try VokabDatabase.makeInMemory()
        let entries = EntryRepository(dbQueue: queue)
        let cache = CacheRepository(dbQueue: queue)
        let quota = QuotaRepository(dbQueue: queue)
        let categories = CategoryService(dbQueue: queue)
        let settings = VokabSettings()
        let runner = MockAgyRunner(response: #"{"pos":"adjective","cefr_level":"B2"}"#)
        let agy = AgyService(runner: runner, settings: settings)
        let capture = CaptureService(agy: agy, entries: entries, cache: cache, quota: quota,
                                     categories: categories, settings: settings)

        let src = SourceContext(appName: "t", url: nil, capturedAt: Date())
        guard case let .pending(id, _) = try capture.beginCapture(text: "stubborn", language: "en", source: src)
        else { return XCTFail("expected .pending") }

        let peak = MaxCounter()
        let worker = CaptureWorker(capture: capture, maxConcurrent: 2,
                                   onChange: {}, onActivity: { peak.observe($0) })
        await worker.enqueueAnalysis(entryId: id)
        await worker.drain()

        XCTAssertGreaterThanOrEqual(peak.max, 1)   // went busy
        XCTAssertEqual(peak.last, 0)               // returned to idle
    }
}

final class ChangeCounter: @unchecked Sendable {
    private let lock = NSLock()
    private var v = 0
    var value: Int { lock.lock(); defer { lock.unlock() }; return v }
    func bump() { lock.lock(); v += 1; lock.unlock() }
}

final class MaxCounter: @unchecked Sendable {
    private let lock = NSLock()
    private var m = 0
    private var l = 0
    var max: Int { lock.lock(); defer { lock.unlock() }; return m }
    var last: Int { lock.lock(); defer { lock.unlock() }; return l }
    func observe(_ v: Int) { lock.lock(); l = v; if v > m { m = v }; lock.unlock() }
}
