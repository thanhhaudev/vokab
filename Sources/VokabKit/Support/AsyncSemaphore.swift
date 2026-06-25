import Foundation

/// A minimal counting semaphore for async/await. Used to cap how many captures
/// run concurrently (SPEC §9 `maxConcurrent`). FIFO fairness for waiters.
///
/// Cancellation-aware: a task cancelled while waiting throws and releases its
/// place in the queue instead of leaking a permit. Prefer `withPermit` over
/// manual `wait()`/`signal()` so the permit is always balanced.
public actor AsyncSemaphore {
    private var available: Int
    /// Boxed so signal() and the cancellation handler can race for the same
    /// waiter by reference identity and resume its continuation exactly once.
    private final class Waiter {
        var continuation: CheckedContinuation<Void, Error>?
    }
    private var waiters: [Waiter] = []

    public init(_ value: Int) { available = max(0, value) }

    /// Acquires a permit, suspending until one is free. Throws `CancellationError`
    /// if the task is cancelled before/while waiting — in that case **no permit is
    /// acquired**, so the caller must not `signal()`. Use `withPermit` to get this
    /// right automatically.
    public func wait() async throws {
        try Task.checkCancellation()
        if available > 0 {
            available -= 1
            return
        }
        let waiter = Waiter()
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Void, Error>) in
                if Task.isCancelled {
                    cont.resume(throwing: CancellationError())
                } else {
                    waiter.continuation = cont
                    waiters.append(waiter)
                }
            }
        } onCancel: {
            Task { await self.cancelWaiter(waiter) }
        }
    }

    /// Releases a permit, handing it straight to the next live waiter if any.
    public func signal() {
        while let waiter = waiters.first {
            waiters.removeFirst()
            if let cont = waiter.continuation {
                waiter.continuation = nil
                cont.resume()            // transfer the permit directly to this waiter
                return
            }
        }
        available += 1
    }

    /// Runs `body` while holding a permit, releasing it on every exit path
    /// (return, throw, or cancellation). The permit is released only if it was
    /// actually acquired, so a cancelled wait can never over-signal.
    public nonisolated func withPermit<T>(_ body: () async throws -> T) async throws -> T {
        try await wait()
        do {
            let result = try await body()
            await signal()
            return result
        } catch {
            await signal()
            throw error
        }
    }

    /// Removes a still-waiting waiter and fails its continuation. No-op if it was
    /// already resumed by `signal()`.
    private func cancelWaiter(_ waiter: Waiter) {
        guard let idx = waiters.firstIndex(where: { $0 === waiter }) else { return }
        waiters.remove(at: idx)
        let cont = waiter.continuation
        waiter.continuation = nil
        cont?.resume(throwing: CancellationError())
    }
}
