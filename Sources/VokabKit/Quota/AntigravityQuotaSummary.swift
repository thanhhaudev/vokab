import Foundation

public struct AntigravityQuotaSummary: Decodable, Equatable, Sendable {
    public var fetchedAt: Date
    public let groups: [Group]
    public let description: String?

    public enum Window: String, Decodable, Sendable, Equatable {
        case weekly, fiveHour, unknown
        public init(from decoder: Decoder) throws {
            let raw = (try? decoder.singleValueContainer().decode(String.self)) ?? ""
            switch raw { case "weekly": self = .weekly; case "5h": self = .fiveHour; default: self = .unknown }
        }
    }

    public struct Bucket: Decodable, Equatable, Sendable {
        public let bucketId: String?
        public let displayName: String?
        public let window: Window
        public let remainingFraction: Double?
        public let resetTime: Date?
        public var utilization: Double? { remainingFraction.map { max(0, min(100, (1 - $0) * 100)) } }
        public var isExhausted: Bool { (remainingFraction ?? 1) <= 0 }
        enum K: String, CodingKey { case bucketId, displayName, window, remainingFraction, resetTime }
        public init(from d: Decoder) throws {
            let c = try d.container(keyedBy: K.self)
            bucketId = try c.decodeIfPresent(String.self, forKey: .bucketId)
            displayName = try c.decodeIfPresent(String.self, forKey: .displayName)
            window = (try? c.decode(Window.self, forKey: .window)) ?? .unknown
            remainingFraction = try c.decodeIfPresent(Double.self, forKey: .remainingFraction)
            if let s = try c.decodeIfPresent(String.self, forKey: .resetTime) {
                resetTime = AntigravityQuotaSummary.iso.date(from: s)
            } else { resetTime = nil }
        }
        public init(bucketId: String?, displayName: String?, window: Window, remainingFraction: Double?, resetTime: Date?) {
            self.bucketId = bucketId; self.displayName = displayName; self.window = window
            self.remainingFraction = remainingFraction; self.resetTime = resetTime
        }
    }

    public struct Group: Decodable, Equatable, Sendable {
        public let displayName: String?
        public let description: String?
        public let buckets: [Bucket]
        public var weekly: Bucket? { buckets.first { $0.window == .weekly } }
        public var fiveHour: Bucket? { buckets.first { $0.window == .fiveHour } }
        public var worstUtilization: Double? { buckets.compactMap { $0.utilization }.max() }
        public var key: String { AntigravityQuotaGroupKey.derive(group: self) }
        enum K: String, CodingKey { case displayName, description, buckets }
        public init(from d: Decoder) throws {
            let c = try d.container(keyedBy: K.self)
            displayName = try c.decodeIfPresent(String.self, forKey: .displayName)
            description = try c.decodeIfPresent(String.self, forKey: .description)
            buckets = (try? c.decodeIfPresent([Bucket].self, forKey: .buckets)) ?? []
        }
        public init(displayName: String?, description: String?, buckets: [Bucket]) {
            self.displayName = displayName; self.description = description; self.buckets = buckets
        }
    }

    enum OuterK: String, CodingKey { case response }
    enum RespK: String, CodingKey { case groups, description }
    public init(from decoder: Decoder) throws {
        fetchedAt = Date(timeIntervalSince1970: 0)
        guard let outer = try? decoder.container(keyedBy: OuterK.self),
              let r = try? outer.nestedContainer(keyedBy: RespK.self, forKey: .response) else {
            groups = []; description = nil; return
        }
        groups = (try? r.decodeIfPresent([Group].self, forKey: .groups)) ?? []
        description = try? r.decodeIfPresent(String.self, forKey: .description)
    }
    public init(fetchedAt: Date, groups: [Group], description: String? = nil) {
        self.fetchedAt = fetchedAt; self.groups = groups; self.description = description
    }

    public static let iso = ISO8601DateFormatter()
    public static let decoder = JSONDecoder()

    public var worstWindowOverall: (group: Group, bucket: Bucket)? {
        groups.flatMap { g in g.buckets.map { (g, $0) } }
            .max(by: { ($0.1.utilization ?? -1) < ($1.1.utilization ?? -1) })
    }
    public var bindingGroupKey: String? {
        groups.max(by: { ($0.worstUtilization ?? -1) < ($1.worstUtilization ?? -1) })?.key
    }
}
