import Foundation

/// Gom item cùng loại vào batch: flush khi đủ `maxBatch` HOẶC sau `window` giây
/// kể từ item đầu của batch hiện tại. `flush` nhận danh sách item → caller build
/// 1 prompt batched + fan-out.
public actor JobCoalescer<Item: Sendable> {
    private let maxBatch: Int
    private let window: TimeInterval
    private let flush: @Sendable ([Item]) async -> Void
    private var pending: [Item] = []
    private var timer: Task<Void, Never>?

    public init(maxBatch: Int, window: TimeInterval, flush: @escaping @Sendable ([Item]) async -> Void) {
        self.maxBatch = max(1, maxBatch); self.window = window; self.flush = flush
    }

    public func submit(_ item: Item) async {
        pending.append(item)
        if pending.count >= maxBatch { await fire(); return }
        if timer == nil {
            timer = Task { [window] in
                try? await Task.sleep(nanoseconds: UInt64(window * 1_000_000_000))
                await self.fire()
            }
        }
    }

    private func fire() async {
        timer?.cancel(); timer = nil
        guard !pending.isEmpty else { return }
        let batch = pending; pending.removeAll()
        await flush(batch)
    }

    /// Test helper: flush phần còn lại + chờ.
    public func waitQuiescent() async {
        if let t = timer { _ = await t.value }
        await fire()
    }
}
