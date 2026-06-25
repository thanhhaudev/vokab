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
                    try? await sem.withPermit {
                        await tracker.enter()
                        try? await Task.sleep(nanoseconds: 20_000_000)
                        await tracker.leave()
                    }
                }
            }
        }
        let peak = await tracker.maxConcurrent
        XCTAssertGreaterThan(peak, 0)
        XCTAssertLessThanOrEqual(peak, 2, "no more than 2 should run at once")
    }

    /// A waiter cancelled while queued must release its slot, not leak a permit:
    /// the freed slot stays acquirable afterwards (no deadlock).
    func testCancelledWaiterReleasesPermit() async throws {
        let sem = AsyncSemaphore(1)
        try await sem.wait()                 // hold the only permit so the next acquirer queues

        let started = expectation(description: "queued waiter started")
        let blocked = Task {
            started.fulfill()
            try await sem.withPermit { try await Task.sleep(nanoseconds: 1_000_000_000) }
        }
        await fulfillment(of: [started], timeout: 1)
        try await Task.sleep(nanoseconds: 30_000_000)   // let it suspend inside wait()
        blocked.cancel()
        let result = await blocked.result
        if case .success = result { XCTFail("cancelled waiter should have thrown") }

        // Release our permit; a fresh acquirer must succeed promptly.
        await sem.signal()
        let acquired = try await withThrowingTaskGroup(of: Bool.self) { group -> Bool in
            group.addTask { (try? await sem.withPermit { true }) ?? false }
            group.addTask { try await Task.sleep(nanoseconds: 1_000_000_000); return false }
            let first = try await group.next() ?? false
            group.cancelAll()
            return first
        }
        XCTAssertTrue(acquired, "permit should be acquirable after a cancelled waiter released it")
    }
}
