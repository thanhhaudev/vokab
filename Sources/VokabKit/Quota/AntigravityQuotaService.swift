import Foundation

public actor AntigravityQuotaService {
    public typealias Detect = @Sendable () throws -> AntigravityProcessInfo?
    public typealias Fetch = @Sendable (_ port: Int, _ csrf: String) async throws -> AntigravityQuotaSummary
    public typealias SpawnFetch = @Sendable () async throws -> AntigravityQuotaSummary

    private let detect: Detect
    private let fetch: Fetch
    private let spawnFetch: SpawnFetch
    private let now: @Sendable () -> Date
    private let ttl: TimeInterval
    private let minRefreshInterval: TimeInterval
    private var cached: AntigravityQuotaSummary?
    private var cachedAt: Date?

    public init(detect: @escaping Detect, fetch: @escaping Fetch, spawnFetch: @escaping SpawnFetch,
                now: @escaping @Sendable () -> Date = Date.init, ttl: TimeInterval = 60,
                minRefreshInterval: TimeInterval = 10) {
        self.detect = detect; self.fetch = fetch; self.spawnFetch = spawnFetch
        self.now = now; self.ttl = ttl; self.minRefreshInterval = minRefreshInterval
    }

    public enum RefreshOutcome: Sendable {
        case refreshed(AntigravityQuotaSummary?)
        case tooSoon(retryAfter: TimeInterval)
    }

    public static func live(launcher: LanguageServerLauncher = LanguageServerLauncher(),
                            client: AntigravityQuotaClient = .live()) -> AntigravityQuotaService {
        AntigravityQuotaService(
            detect: { try launcher.detector.detect() },
            fetch: { port, csrf in try await client.fetchQuota(port: port, csrfToken: csrf) },
            spawnFetch: {
                let csrf = UUID().uuidString
                let s = try await launcher.spawn(csrf: csrf)
                defer { launcher.terminate(pid: s.pid) }
                return try await client.fetchQuota(port: s.port, csrfToken: csrf)
            })
    }

    /// Trả quota (cache TTL); nil nếu không lấy được (app chưa cài / chưa đăng nhập).
    public func summary(force: Bool = false) async -> AntigravityQuotaSummary? {
        if !force, let c = cached, let at = cachedAt, now().timeIntervalSince(at) < ttl { return c }
        do {
            let s = try await fetchFresh()
            cached = s; cachedAt = now()
            return s
        } catch { return cached }
    }

    /// Reload THỦ CÔNG với sàn cứng chống rate-limit.
    public func refresh() async -> RefreshOutcome {
        if let at = cachedAt {
            let elapsed = now().timeIntervalSince(at)
            if elapsed < minRefreshInterval { return .tooSoon(retryAfter: minRefreshInterval - elapsed) }
        }
        return .refreshed(await summary(force: true))
    }

    /// Refresh CHỈ khi server đã detect được (rẻ) — dùng sau khi vokab tự tiêu quota.
    public func refreshIfCheap() async {
        if ((try? detect()) ?? nil) != nil { _ = await summary(force: true) }
    }

    private func fetchFresh() async throws -> AntigravityQuotaSummary {
        if let info = try detect(), let port = info.listeningPorts.first {
            return try await fetch(port, info.csrfToken)
        }
        return try await spawnFetch()
    }
}
