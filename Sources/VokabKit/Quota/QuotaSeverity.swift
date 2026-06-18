import Foundation

public enum QuotaSeverity: Sendable, Equatable { case ok, amber, red
    /// amber khi remaining ≤ 0.20, red khi ≤ 0.05. nil → ok.
    public static func forRemaining(_ remaining: Double?) -> QuotaSeverity {
        guard let r = remaining else { return .ok }
        if r <= 0.05 { return .red }
        if r <= 0.20 { return .amber }
        return .ok
    }
}

/// Debounce: chỉ báo MỘT LẦN khi lần đầu chạm red; reset khi rời red.
public struct RedNotificationGate: Sendable {
    private var inRed = false
    public init() {}
    public mutating func shouldNotify(severity: QuotaSeverity) -> Bool {
        if severity == .red {
            if inRed { return false }
            inRed = true; return true
        } else {
            inRed = false; return false
        }
    }
}
