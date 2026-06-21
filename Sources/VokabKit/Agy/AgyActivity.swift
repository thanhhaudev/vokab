import Foundation

/// Thread-safe in-flight counter for agy calls.
///
/// Every `AgyService` call brackets itself with `begin()`/`end()`, so this counts
/// ALL background AI work — capture analysis, enrichment, backfill, translation,
/// paragraph extraction, production grading — through one chokepoint. `onChange`
/// reports the new in-flight count (off the main thread) so the UI can show a
/// single "AI is working" indicator. Set the callback with `setOnChange` once at
/// wiring time; reads and writes are serialized by an internal lock.
public final class AgyActivity: @unchecked Sendable {
    private let lock = NSLock()
    private var count = 0
    private var onChange: (@Sendable (Int) -> Void)?

    public init() {}

    /// Registers the in-flight-count observer. Safe to call once at setup.
    public func setOnChange(_ callback: @escaping @Sendable (Int) -> Void) {
        lock.lock(); onChange = callback; lock.unlock()
    }

    /// Marks one agy call as started; reports the new count.
    public func begin() { adjust(by: 1) }

    /// Marks one agy call as finished; reports the new count (never below zero).
    public func end() { adjust(by: -1) }

    private func adjust(by delta: Int) {
        lock.lock()
        count = max(0, count + delta)
        let current = count
        let callback = onChange
        lock.unlock()
        callback?(current)
    }
}
