import Foundation

/// Where a capture came from (SPEC §6). Always recorded with each entry.
public struct SourceContext: Sendable, Equatable {
    public var appName: String?
    public var url: String?
    public var capturedAt: Date

    public init(appName: String? = nil, url: String? = nil, capturedAt: Date = Date()) {
        self.appName = appName
        self.url = url
        self.capturedAt = capturedAt
    }
}
