import Foundation
import VokabKit

/// Sidebar filter selection for the Library.
enum LibraryFilter: Hashable {
    case due
    case all
    case week
    case cefr(String)
    case language(String)
    case category(String)
    case uncategorized
    case type(String)
}

/// A list row: entry + its scheduling status for the due-dot and interval label.
struct LibraryRow: Identifiable, Hashable {
    let entry: Entry
    let dueStatus: Theme.DueStatus
    let intervalLabel: String
    /// Decoded once at row-construction time (not per render).
    let meaning: String?
    let cefr: String?
    var id: Int64 { entry.id ?? 0 }
}

@MainActor
final class LibraryViewModel: ObservableObject {
    @Published var filter: LibraryFilter = .due

    @Published private(set) var entries: [Entry] = []
    @Published private(set) var states: [Int64: ReviewState] = [:]
    @Published private(set) var dueCount = 0
    @Published private(set) var streak = 0
    /// All rows, decoded once per load (not per render). `rows` filters this.
    @Published private(set) var allRows: [LibraryRow] = []
    @Published private(set) var categoryCounts: [String: Int] = [:]
    @Published private(set) var uncategorizedCount = 0
    @Published private(set) var categoryColorIndex: [String: Int] = [:]
    // Sidebar statcard (mockup #4): quota used/limit + on-disk DB size.
    @Published private(set) var quotaUsed = 0
    @Published private(set) var quotaLimit = 0
    @Published private(set) var diskBytes: Int64 = 0
    // Dashboard insight series (populated in load()).
    // Antigravity real quota
    @Published var antigravityQuota: AntigravityQuotaSummary?
    @Published var quotaReloading = false
    /// Seconds remaining before a manual quota reload is allowed again (set on a
    /// too-soon reload). The view formats the localized tooltip; nil = no cooldown.
    @Published var quotaCooldownRetry: Int?

    private let env: AppEnvironment
    init(env: AppEnvironment) { self.env = env }

    /// Loads from the DB and builds rows once. Runs synchronously on the main
    /// thread — this is fast (the beachball came from the agy subprocess, now
    /// async) and avoids the observation pitfalls of an off-main publish.
    func load() {
        let now = Date()
        entries = (try? env.entries.all()) ?? []
        // Single read for all review states (no per-entry N+1).
        let map = (try? env.review.allStates()) ?? [:]
        states = map
        dueCount = (try? env.review.dueCount(on: now)) ?? 0
        streak = (try? env.reviewLog.streak()) ?? 0
        allRows = Self.buildRows(entries: entries, states: map,
                                 lang: env.settings.meaningLanguage, now: now)
        categoryCounts = (try? env.entries.categoryCounts()) ?? [:]
        uncategorizedCount = (try? env.entries.uncategorizedCount()) ?? 0
        categoryColorIndex = (try? env.dbQueue.read { db in
            try Category.fetchAll(db).reduce(into: [String: Int]()) { $0[$1.name] = $1.colorIndex }
        }) ?? [:]
        quotaUsed = (try? env.quota.count(on: now)) ?? 0
        quotaLimit = env.settings.dailyLimit
        diskBytes = (try? VokabDatabase.defaultPath())
            .flatMap { try? FileManager.default.attributesOfItem(atPath: $0)[.size] as? Int64 } ?? 0
    }

    /// Human-readable disk size for the statcard (e.g. "4.2 MB").
    var diskLabel: String {
        ByteCountFormatter.string(fromByteCount: diskBytes, countStyle: .file)
    }

    func loadQuota() {
        Task { @MainActor in
            self.antigravityQuota = await env.antigravityQuota.summary()
            env.evaluateQuotaAlert(self.antigravityQuota)
        }
    }

    func reloadQuota() {
        guard !quotaReloading else { return }
        quotaReloading = true
        Task { @MainActor in
            defer { quotaReloading = false }
            switch await env.antigravityQuota.refresh() {
            case let .refreshed(s):
                antigravityQuota = s
                env.evaluateQuotaAlert(s)
                quotaCooldownRetry = nil
            case let .tooSoon(retryAfter): quotaCooldownRetry = Int(retryAfter.rounded())
            }
        }
    }

    /// Categories that have at least one entry, sorted by name (sidebar order).
    var categories: [String] { categoryCounts.keys.sorted() }

    /// Pure row construction (decode happens here, once).
    nonisolated private static func buildRows(entries: [Entry], states: [Int64: ReviewState],
                                              lang: String, now: Date) -> [LibraryRow] {
        func state(_ e: Entry) -> ReviewState? { e.id.flatMap { states[$0] } }
        return entries
            .sorted { (state($0)?.dueDate ?? .distantFuture) < (state($1)?.dueDate ?? .distantFuture) }
            .map { entry in
                let summary = CardDecoding.summary(entry, meaningLanguage: lang)
                return LibraryRow(entry: entry,
                                  dueStatus: Self.status(state(entry), now),
                                  intervalLabel: Self.intervalLabel(state(entry), now),
                                  meaning: summary.meaning, cefr: summary.cefr)
            }
    }

    var total: Int { entries.count }

    var addedThisWeek: Int {
        let weekAgo = Date().addingTimeInterval(-7 * 86_400)
        return entries.filter { $0.capturedAt >= weekAgo }.count
    }

    var reviewedCount: Int { states.values.reduce(0) { $0 + $1.reviewCount } }

    /// Number of overdue cards (for the Due-today card's red-vs-amber accent).
    var overdueCount: Int { allRows.filter { $0.dueStatus == .overdue }.count }

    var cefrLevels: [String] { Set(entries.compactMap { $0.cefr?.lowercased() }).sorted() }
    var languages: [String] { Set(entries.map { $0.language.lowercased() }).sorted() }

    /// Distinct entry types present, in natural order (word → phrase → paragraph item).
    var types: [String] {
        let present = Set(entries.map(\.type))
        return CardType.allCases.map(\.rawValue).filter(present.contains)
    }

    /// Localized label for an entry type (also used by the sidebar Type rows).
    static func typeLabel(_ raw: String) -> String {
        switch CardType(rawValue: raw) {
        case .word: return L.t("Words", "Từ")
        case .phrase: return L.t("Phrases", "Cụm từ")
        case .paragraphItem: return L.t("Paragraph", "Đoạn")
        case .none: return raw
        }
    }

    func count(forCEFR level: String) -> Int {
        entries.filter { $0.cefr?.lowercased() == level.lowercased() }.count
    }
    func count(forLanguage lang: String) -> Int {
        entries.filter { $0.language.lowercased() == lang.lowercased() }.count
    }
    func count(forType t: String) -> Int {
        entries.filter { $0.type == t }.count
    }
    var weekCount: Int { addedThisWeek }

    /// Rows for the active filter, filtering the prebuilt `allRows` (no decode).
    var rows: [LibraryRow] {
        let weekAgo = Date().addingTimeInterval(-7 * 86_400)
        switch filter {
        case .all:
            return allRows
        case .due:
            return allRows.filter { $0.dueStatus != .future }
        case .week:
            return allRows.filter { $0.entry.capturedAt >= weekAgo }
        case .cefr(let level):
            return allRows.filter { $0.entry.cefr?.lowercased() == level.lowercased() }
        case .language(let lang):
            return allRows.filter { $0.entry.language.lowercased() == lang.lowercased() }
        case .category(let name):
            return allRows.filter { $0.entry.category == name }
        case .uncategorized:
            return allRows.filter { $0.entry.category == nil }
        case .type(let t):
            return allRows.filter { $0.entry.type == t }
        }
    }

    var filterTitle: String {
        switch filter {
        case .due: return L.t("Due today", "Đến hạn hôm nay")
        case .all: return L.t("All words", "Tất cả")
        case .week: return L.t("This week", "Tuần này")
        case .cefr(let l): return l.uppercased()
        case .language(let l): return l.uppercased()
        case .category(let name): return name
        case .uncategorized: return L.t("Uncategorized", "Chưa phân loại")
        case .type(let t): return Self.typeLabel(t)
        }
    }

    // MARK: scheduling helpers (pure)

    nonisolated private static func status(_ s: ReviewState?, _ now: Date) -> Theme.DueStatus {
        Theme.DueStatus.of(s, now: now)
    }

    nonisolated private static func intervalLabel(_ s: ReviewState?, _ now: Date) -> String {
        guard let s else { return "new" }
        if s.reviewCount == 0 { return "new" }
        let days = Calendar.current.dateComponents([.day],
            from: Calendar.current.startOfDay(for: now),
            to: Calendar.current.startOfDay(for: s.dueDate)).day ?? 0
        if days <= 0 { return "today" }
        if days == 1 { return "1 day" }
        return "\(days) days"
    }
}
