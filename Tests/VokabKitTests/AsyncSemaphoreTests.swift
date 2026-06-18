import XCTest
@testable import VokabKit

private actor ConcurrencyTracker {
    private(set) var maxConcurrent = 0
    private var current = 0
    func enter() { current += 1; maxConcurrent = max(maxConcurrent, current) }
    func leave() { current -= 1 }
}

final class AsyncSemaphoreTests: XCTestCase {
    func testCapsConcurrency() async {
        let sem = AsyncSemaphore(2)
        let tracker = ConcurrencyTracker()
        await withTaskGroup(of: Void.self) { group in
            for _ in 0..<6 {
                group.addTask {
                    await sem.wait()
                    await tracker.enter()
                    try? await Task.sleep(nanoseconds: 20_000_000)
                    await tracker.leave()
                    await sem.signal()
                }
            }
        }
        let peak = await tracker.maxConcurrent
        XCTAssertGreaterThan(peak, 0)
        XCTAssertLessThanOrEqual(peak, 2, "no more than 2 should run at once")
    }
}
