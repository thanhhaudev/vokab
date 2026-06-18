import Foundation

/// A minimal counting semaphore for async/await. Used to cap how many captures
/// run concurrently (SPEC §9 `maxConcurrent`). FIFO fairness for waiters.
public actor AsyncSemaphore {
    private var available: Int
    private var waiters: [CheckedContinuation<Void, Never>] = []

    public init(_ value: Int) { available = max(0, value) }

    /// Acquires a permit, suspending until one is free.
    public func wait() async {
        if available > 0 {
            available -= 1
            return
        }
        await withCheckedContinuation { waiters.append($0) }
    }

    /// Releases a permit, waking the next waiter if any.
    public func signal() {
        if waiters.isEmpty {
            available += 1
        } else {
            waiters.removeFirst().resume()
        }
    }
}
