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
}

final class ChangeCounter: @unchecked Sendable {
    private let lock = NSLock()
    private var v = 0
    var value: Int { lock.lock(); defer { lock.unlock() }; return v }
    func bump() { lock.lock(); v += 1; lock.unlock() }
}
