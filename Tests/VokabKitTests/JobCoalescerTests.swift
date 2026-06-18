import XCTest
@testable import VokabKit

final class JobCoalescerTests: XCTestCase {
    func test_flushesWhenReachingCap() async {
        let flushed = FlushRecorder()
        let c = JobCoalescer<Int64>(maxBatch: 3, window: 100,
            flush: { ids in flushed.record(ids) })
        await c.submit(1); await c.submit(2); await c.submit(3)
        await c.waitQuiescent()
        XCTAssertEqual(flushed.batches, [[1, 2, 3]])
    }
    func test_flushesPartialOnWindow() async {
        let flushed = FlushRecorder()
        let c = JobCoalescer<Int64>(maxBatch: 10, window: 0.05,
            flush: { ids in flushed.record(ids) })
        await c.submit(1); await c.submit(2)
        await c.waitQuiescent()
        XCTAssertEqual(flushed.batches, [[1, 2]])
    }
}
final class FlushRecorder: @unchecked Sendable {
    private let lock = NSLock(); private(set) var batches: [[Int64]] = []
    func record(_ ids: [Int64]) { lock.lock(); batches.append(ids); lock.unlock() }
}
