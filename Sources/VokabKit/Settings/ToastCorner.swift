import Foundation

/// Screen corner the capture toast stack grows from.
public enum ToastCorner: String, Codable, Sendable, CaseIterable {
    case topTrailing, topLeading, bottomTrailing, bottomLeading
}
