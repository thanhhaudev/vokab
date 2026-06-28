import Foundation
import GRDB
import VokabKit

/// Owns the database and the VokabKit services, and injects them into SwiftUI.
@MainActor
final class AppEnvironment: ObservableObject {
    /// The app-wide environment, set when the app builds its environment.
    static private(set) var shared: AppEnvironment?

    /// Published so a Settings change applies to open windows immediately (no
    /// relaunch) for settings read live from `env.settings` — accent, cloze /
    /// production thresholds, meaning language. (Settings captured by services at
    /// init — agy model/path/timeout — still take effect on next launch.)
    @Published var settings: VokabSettings
    @Published var activeAnalyses: Int = 0
    /// Breathing alpha (0.4…1.0) for the menubar activity dot while analyzing.
    /// Driven by a timer only when `activeAnalyses > 0`; 1.0 when idle.
    @Published var pulse: Double = 1.0
    private var pulseTimer: Timer?
    private var pulseTick = 0
    let dbQueue: DatabaseQueue
    /// False when the on-disk database couldn't be opened and we fell back to an
    /// in-memory database (data is lost on quit). The UI surfaces a banner so the
    /// user isn't silently capturing into a throwaway store.
    let isPersistent: Bool
    let entries: EntryRepository
    let review: ReviewRepository
    let reviewLog: ReviewLogRepository
    let cache: CacheRepository
    let quota: QuotaRepository
    let agy: AgyService
    let categories: CategoryService
    let capture: CaptureService
    let enrichment: EnrichmentService
    let batchEnricher: BatchEnricher
    let prefetcher: EnrichmentPrefetcher
    let categoryBackfiller: CategoryBackfiller
    let relationsBackfiller: RelationsBackfiller
    let phraseErrorBackfiller: PhraseErrorBackfiller
    let translation: TranslationService
    let antigravityQuota: AntigravityQuotaService
    let captureWorker: CaptureWorker
    /// Tracks all in-flight agy calls; drives the menubar activity dot.
    private let agyActivity: AgyActivity
    private var redQuotaGate = RedNotificationGate()

    init(queue: DatabaseQueue, settings: VokabSettings, isPersistent: Bool = true) {
        self.settings = settings
        self.dbQueue = queue
        self.isPersistent = isPersistent
        let entries = EntryRepository(dbQueue: queue)
        let cache = CacheRepository(dbQueue: queue)
        let quota = QuotaRepository(dbQueue: queue)
        let agyActivity = AgyActivity()
        let agy = AgyService(runner: AgyClient(settings: settings), settings: settings, activity: agyActivity)
        self.agyActivity = agyActivity
        let categories = CategoryService(dbQueue: queue)
        self.entries = entries
        self.cache = cache
        self.quota = quota
        self.review = ReviewRepository(dbQueue: queue)
        self.reviewLog = ReviewLogRepository(dbQueue: queue)
        self.agy = agy
        self.categories = categories
        self.capture = CaptureService(agy: agy, entries: entries, cache: cache,
                                      quota: quota, categories: categories, settings: settings)
        self.enrichment = EnrichmentService(agy: agy, entries: entries)
        self.batchEnricher = BatchEnricher(
            agy: agy, entries: entries, fallback: self.enrichment,
            onChange: { Task { @MainActor in WindowManager.notifyDataChanged() } })
        self.prefetcher = EnrichmentPrefetcher(
            enrichment: self.enrichment, entries: entries,
            batchEnricher: self.batchEnricher,
            onChange: { Task { @MainActor in WindowManager.notifyDataChanged() } })
        self.categoryBackfiller = CategoryBackfiller(agy: agy, entries: entries, categories: categories)
        self.relationsBackfiller = RelationsBackfiller(agy: agy, entries: entries)
        self.phraseErrorBackfiller = PhraseErrorBackfiller(agy: agy, entries: entries)
        self.translation = TranslationService(agy: agy, cache: cache)
        self.antigravityQuota = AntigravityQuotaService.live()
        let onWorkerChange: @Sendable () -> Void = {
            Task { @MainActor in WindowManager.notifyDataChanged() }
        }
        let onWorkerFailure: @Sendable (Int64) -> Void = { entryId in
            Task { @MainActor in
                let word = ((try? entries.entry(id: entryId)) ?? nil)?.rawText ?? ""
                NotificationManager.shared.postFailed(word: word, entryId: entryId)
            }
        }
        let onWorkerComplete: @Sendable (Int64, CaptureService.AnalysisReport) -> Void = { id, report in
            Task { @MainActor in CaptureController.shared.entryCompleted(id, report) }
        }
        self.captureWorker = CaptureWorker(
            capture: self.capture, maxConcurrent: settings.maxConcurrent,
            onChange: onWorkerChange, onFailure: onWorkerFailure, onComplete: onWorkerComplete)
        // All stored properties are now set, so `self` may be captured. The menubar
        // activity dot reflects EVERY agy call — capture analysis, enrichment,
        // backfill, translation, extraction, grading — via the shared tracker.
        agyActivity.setOnChange { [weak self] count in
            Task { @MainActor in self?.updateActivity(count) }
        }
    }

    /// Updates the activity count and starts/stops the dot's pulse accordingly.
    @MainActor private func updateActivity(_ count: Int) {
        activeAnalyses = count
        if count > 0 { startPulse() } else { stopPulse() }
    }

    @MainActor private func startPulse() {
        guard pulseTimer == nil else { return }
        // ~15fps is smooth enough for a breathing dot and cheap to redraw.
        let timer = Timer(timeInterval: 1.0 / 15.0, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.advancePulse() }
        }
        // .common so it keeps firing while a menu/popover is in tracking mode.
        RunLoop.main.add(timer, forMode: .common)
        pulseTimer = timer
    }

    @MainActor private func advancePulse() {
        pulseTick += 1
        let period = 1.2   // seconds per breath
        let t = Double(pulseTick) / 15.0
        let s = 0.5 + 0.5 * sin(2 * Double.pi * t / period)
        pulse = 0.4 + 0.6 * s
    }

    @MainActor private func stopPulse() {
        pulseTimer?.invalidate()
        pulseTimer = nil
        pulseTick = 0
        pulse = 1.0
    }

    /// Re-queues a failed entry's background analysis.
    func retryAnalysis(id: Int64) {
        try? entries.markAnalyzingAgain(id: id)
        Task { await captureWorker.enqueueAnalysis(entryId: id) }
    }

    /// Fires a one-shot notification when the selected model-group's quota goes red.
    func evaluateQuotaAlert(_ summary: AntigravityQuotaSummary?) {
        guard let summary else { return }
        let key = AntigravityModelGroup.groupKey(forModel: settings.model)
        let group = summary.groups.first { $0.key == key }
            ?? summary.groups.first { $0.key == summary.bindingGroupKey }
        guard let group else { return }
        let remaining = group.buckets.compactMap { $0.remainingFraction }.min()
        let severity = QuotaSeverity.forRemaining(remaining)
        guard redQuotaGate.shouldNotify(severity: severity) else { return }
        let pct = Int(((remaining ?? 0) * 100).rounded())
        let name = group.displayName ?? L.t("Quota", "Hạn mức")
        NotificationManager.shared.postQuotaAlert(
            title: L.t("Quota almost out", "Quota sắp hết"),
            body: L.t("\(name): \(pct)% left", "\(name): còn \(pct)%"))
    }

    convenience init(dbPath: String, settings: VokabSettings) throws {
        self.init(queue: try VokabDatabase.makeQueue(path: dbPath), settings: settings)
    }

    /// Production environment at the default on-disk location.
    static func makeDefault() throws -> AppEnvironment {
        try AppEnvironment(dbPath: try VokabDatabase.defaultPath(),
                           settings: SettingsStore.load())
    }

    /// Best-effort environment: the on-disk DB, or an in-memory fallback if the
    /// default location cannot be opened (so the app still launches).
    static func makeResilient() -> AppEnvironment {
        let env: AppEnvironment
        if let made = try? makeDefault() {
            env = made
        } else {
            let queue: DatabaseQueue
            if let mem = try? VokabDatabase.makeInMemory() {
                queue = mem
            } else {
                queue = try! DatabaseQueue()
            }
            // In-memory fallback: the app runs but captures won't survive a quit.
            env = AppEnvironment(queue: queue, settings: SettingsStore.load(), isPersistent: false)
        }
        AppEnvironment.shared = env
        let prettifyFlagKey = "vokab.categoryPrettifyBackfill.v1"
        if !UserDefaults.standard.bool(forKey: prettifyFlagKey) {
            Task.detached {
                if (try? env.categories.prettifyExistingNames()) != nil {
                    UserDefaults.standard.set(true, forKey: prettifyFlagKey)
                }
            }
        }
        Task { await env.captureWorker.resumePending() }
        return env
    }

    // MARK: - Headless verification

    /// When `VOKAB_SELFTEST=1`, opens the DB (seeding first if `VOKAB_SEED=1`),
    /// prints counts to stdout, and exits. Lets the full app↔VokabKit wiring be
    /// verified without a GUI. Returns without effect otherwise.
    static func runSelfTestIfRequested() {
        guard ProcessInfo.processInfo.environment["VOKAB_SELFTEST"] == "1" else { return }
        do {
            let path = try ProcessInfo.processInfo.environment["VOKAB_DB"] ?? VokabDatabase.defaultPath()
            let env = try AppEnvironment(dbPath: path, settings: VokabSettings())
            if ProcessInfo.processInfo.environment["VOKAB_SEED"] == "1" {
                try env.seedSampleData()
            }
            if let word = ProcessInfo.processInfo.environment["VOKAB_CAPTURE_SMOKE"], !word.isEmpty {
                runCaptureSmoke(env: env, word: word)
            }
            let total = try env.entries.all().count
            let due = try env.review.dueCount(on: Date())
            FileHandle.standardOutput.write(Data("vokab-selftest: entries=\(total) due=\(due)\n".utf8))
            if ProcessInfo.processInfo.environment["VOKAB_LIBRARY_SMOKE"] == "1" {
                let model = LibraryViewModel(env: env)
                model.load()
                let dueRows = model.rows.count
                FileHandle.standardOutput.write(
                    Data("vokab-library: allRows=\(model.allRows.count) dueRows=\(dueRows)\n".utf8))
            }
            exit(0)
        } catch {
            FileHandle.standardError.write(Data("vokab-selftest: ERROR \(error)\n".utf8))
            exit(1)
        }
    }

    /// Runs one real capture through the full wrapper (CaptureService → AgyService
    /// → AgyClient) with the app's default settings, printing the outcome. Used to
    /// smoke-test the agy integration from a headless launch.
    private static func runCaptureSmoke(env: AppEnvironment, word: String) {
        let semaphore = DispatchSemaphore(value: 0)
        let box = SmokeBox()
        // Detached so it does not inherit the main actor — the main thread is
        // blocked on the semaphore below and must not be needed for progress.
        Task.detached {
            let source = SourceContext(appName: "smoke", url: nil, capturedAt: Date())
            var line = "capture-smoke: no result"
            do {
                let result = try await env.capture.capture(text: word, language: "en", source: source)
                line = "capture-smoke: OK type=\(result.type.rawValue) entryId=\(result.entryId.map(String.init) ?? "nil") dup=\(result.wasDuplicate)"
            } catch {
                line = "capture-smoke: FAILED \(error)"
            }
            box.line = line
            semaphore.signal()
        }
        semaphore.wait()
        FileHandle.standardOutput.write(Data("\(box.line)\n".utf8))
    }

    /// Thread-safe-enough box to carry the smoke result out of the detached task
    /// (writer signals, reader waits on the semaphore — no concurrent access).
    private final class SmokeBox: @unchecked Sendable {
        var line = "capture-smoke: no result"
    }

    /// Inserts a few representative entries (word, phrase, paragraph item) for
    /// manual/visual verification. Idempotent-ish: skips if data already exists.
    func seedSampleData() throws {
        guard try entries.all().isEmpty else { return }
        let now = Date()
        let src = SourceContext(appName: "Seed", url: "https://example.com", capturedAt: now)

        let word = #"{"ipa":"/ɪˈfɛmərəl/","pos":"adjective","meaning_vi":"phù du, chóng tàn","meaning_en":"lasting a very short time","examples":["an ephemeral trend"],"etymology":"Greek ephēmeros","cefr_level":"C1","register":"formal","frequency":"low","synonyms":["transient","fleeting"],"antonyms":["permanent"],"word_family":["ephemerality"]}"#
        _ = try entries.insertCapture(
            Entry(rawText: "ephemeral", type: CardType.word.rawValue, language: "en",
                  sourceApp: src.appName, sourceURL: src.url, capturedAt: now,
                  aiResult: word, cefr: "c1", frequency: "low"),
            dueDate: now.addingTimeInterval(-3600))

        let phrase = #"{"type":"phrasal_verb","formula_pattern":"give up + on + sb/sth","pattern_confidence":0.9,"meaning_vi":"từ bỏ ai/việc gì","meaning_en":"stop trying","register":"neutral","cefr_level":"B1","separable":true,"object_type":"noun phrase","usage_note":"informal","examples":["Don't give up on me"],"variations":["give up"],"common_errors":[{"sentence":"Don't give up _____ me.","answer":"on","options":["on","to","at"],"note_vi":"give up + on + sb"}],"related_phrases":["throw in the towel"]}"#
        _ = try entries.insertCapture(
            Entry(rawText: "give up on", type: CardType.phrase.rawValue, language: "en",
                  sourceApp: src.appName, sourceURL: src.url, capturedAt: now,
                  aiResult: phrase, cefr: "b1"),
            dueDate: now)

        let item = #"{"word":"ubiquitous","cefr":"C1","pos":"adjective","meaning_vi":"có mặt khắp nơi","reason_to_learn":"academic, high utility"}"#
        _ = try entries.insertCapture(
            Entry(rawText: "ubiquitous", type: CardType.paragraphItem.rawValue, language: "en",
                  sourceApp: src.appName, sourceURL: src.url, capturedAt: now,
                  aiResult: item, cefr: "c1"),
            dueDate: now.addingTimeInterval(86_400))
    }
}
