import Foundation

/// Chạy phân tích core (tier-1) ở nền sau `beginCapture`, bounded concurrency.
public actor CaptureWorker {
    private let capture: CaptureService
    private let gate: AsyncSemaphore
    private let onChange: @Sendable () -> Void
    private let onFailure: (@Sendable (Int64) -> Void)?
    private let onComplete: (@Sendable (Int64, CaptureService.AnalysisOutcome) -> Void)?
    private let onActivity: (@Sendable (Int) -> Void)?
    private var inflight = Set<Int64>()
    private var tasks: [Int64: Task<Void, Never>] = [:]

    public init(capture: CaptureService, maxConcurrent: Int = 2,
                onChange: @escaping @Sendable () -> Void,
                onFailure: (@Sendable (Int64) -> Void)? = nil,
                onComplete: (@Sendable (Int64, CaptureService.AnalysisOutcome) -> Void)? = nil,
                onActivity: (@Sendable (Int) -> Void)? = nil) {
        self.capture = capture
        self.gate = AsyncSemaphore(max(1, maxConcurrent))
        self.onChange = onChange
        self.onFailure = onFailure
        self.onComplete = onComplete
        self.onActivity = onActivity
    }

    /// Lên lịch phân tích một entry pending. Coalesce: bỏ qua nếu đang chạy.
    public func enqueueAnalysis(entryId: Int64) {
        guard !inflight.contains(entryId) else { return }
        inflight.insert(entryId)
        onActivity?(inflight.count)
        tasks[entryId] = Task { await self.run(entryId) }
    }

    /// Lên lịch lại mọi entry còn 'analyzing' (resume sau relaunch/crash).
    public func resumePending() {
        let ids = (try? capture.pendingEntryIdsForResume()) ?? []
        for id in ids { enqueueAnalysis(entryId: id) }
    }

    private func run(_ id: Int64) async {
        // Cancelled while queued (e.g. shutdown) → skip; never over-signal.
        let outcome = (try? await gate.withPermit {
            await capture.runAnalysis(entryId: id)
        }) ?? .skipped
        inflight.remove(id)
        onActivity?(inflight.count)
        tasks[id] = nil
        onChange()
        if outcome == .failed { onFailure?(id) }
        onComplete?(id, outcome)
    }

    /// Test helper: chờ mọi job đã enqueue hoàn tất.
    public func drain() async {
        let snapshot = Array(tasks.values)
        for t in snapshot { _ = await t.value }
    }
}
