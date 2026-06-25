import Foundation
import AppKit
import VokabKit

/// Coordinates a capture from any entry point (menubar field, Services): builds
/// source context, shows the toast, runs `CaptureService`, and posts a
/// notification. Serializes captures to honor the concurrency cap.
@MainActor
final class CaptureController: ObservableObject {
    static let shared = CaptureController()
    var env: AppEnvironment?

    // Caps concurrent captures to settings.maxConcurrent (SPEC §9). Rebuilt if
    // the limit changes.
    private var gate: AsyncSemaphore?
    private var gateLimit = 0
    /// Last paragraph capture's candidates, so the toast's View can reopen extraction.
    private var pendingParagraph: (items: [ParagraphItem], translationVi: String?, source: SourceContext, language: String, rawText: String, failedChunks: Int)?
    /// Per-entry toast updaters, fired by `entryCompleted` when background analysis finishes.
    private var pendingToasts: [Int64: @MainActor (CaptureService.AnalysisOutcome) -> Void] = [:]

    /// Called by CaptureWorker (via AppEnvironment) when an entry's analysis finishes;
    /// updates the toast that was registered for it in the `.pending` case.
    @MainActor func entryCompleted(_ id: Int64, _ outcome: CaptureService.AnalysisOutcome) {
        guard let handler = pendingToasts.removeValue(forKey: id) else { return }
        handler(outcome)
    }

    private func captureGate(limit: Int) -> AsyncSemaphore {
        if gate == nil || gateLimit != limit {
            gate = AsyncSemaphore(max(1, limit))
            gateLimit = limit
        }
        return gate!
    }

    /// - Parameters:
    ///   - language: overrides language auto-detection when non-nil.
    ///   - type: forces the capture type (Auto = nil); from the segmented control.
    ///   - minLevel: paragraph extraction min CEFR when type resolves to paragraph.
    func capture(_ text: String, source: SourceContext? = nil,
                 language languageOverride: String? = nil,
                 type forcedType: CardType? = nil,
                 minLevel: CEFR? = nil) {
        guard let env else { return }
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        // Pure-punctuation selections (e.g. ",,," or "...") clean to nothing —
        // skip before showing a toast (matches CaptureService.beginCapture .empty).
        let probeType = forcedType ?? InputClassifier.classify(trimmed)
        if probeType != .paragraphItem, InputCleaner.clean(trimmed, type: probeType).isEmpty { return }

        ToastCenter.shared.corner = env.settings.toastPosition
        let model = ToastCenter.shared.present()
        model.meaningLanguage = env.settings.meaningLanguage
        model.phase = .analyzing(trimmed)
        model.onView = { [weak self] in self?.openLibrary() }   // word/phrase; paragraph reassigns below
        model.onUndo = { entryId in
            try? env.entries.delete(id: entryId)
            WindowManager.notifyDataChanged()
            ToastCenter.shared.dismiss(model)
        }

        let src = source ?? SourceContext(
            appName: NSWorkspace.shared.frontmostApplication?.localizedName,
            url: nil, capturedAt: Date())
        let autoDetect = env.settings.autoDetectLanguage
        let fallbackLanguage = env.settings.defaultCaptureLanguage

        let gate = captureGate(limit: env.settings.maxConcurrent)
        Task {
            // Hold a concurrency permit for the whole capture; `withPermit` always
            // releases it, even on throw or cancellation (SPEC §9).
            try? await gate.withPermit {
                // Language detection (NLP) off the main actor — paragraph-size text
                // would otherwise block the UI.
                let language: String
                if let languageOverride { language = languageOverride }
                else if autoDetect {
                    let fb = fallbackLanguage
                    language = await Task.detached { LanguageDetector.detect(trimmed, default: fb) }.value
                }
                else { language = fallbackLanguage }
                do {
                    let began = try env.capture.beginCapture(text: trimmed, language: language,
                                                             source: src, forcedType: forcedType)
                    switch began {
                    case .paragraph:
                        // Paragraph: fall through to the original async path so the
                        // extraction window opens as before.
                        let result = try await env.capture.capture(text: trimmed, language: language,
                                                                   source: src, forcedType: forcedType,
                                                                   minLevelOverride: minLevel)
                        let summary = Self.summary(result, text: trimmed, env: env)
                        pendingParagraph = (result.paragraphItems, result.translationVi, src, language, trimmed, result.failedChunks)
                        model.onView = { [weak self] in self?.reopenExtraction() }
                        model.phase = .resolved(entry: nil, fallback: summary, wasDuplicate: false)
                        WindowManager.shared.showExtraction(items: result.paragraphItems,
                                                            translationVi: result.translationVi,
                                                            source: src, language: language, rawText: trimmed,
                                                            failedChunks: result.failedChunks)

                    case .duplicate(let entryId, _):
                        let entry = try? env.entries.entry(id: entryId)
                        let dupSummary = entry.map {
                            Self.summarize(entry: $0, text: trimmed, wasDuplicate: true, env: env)
                        } ?? trimmed
                        model.onView = { WindowManager.shared.showCaptureResult(entryId: entryId) }
                        model.phase = .resolved(entry: entry, fallback: dupSummary, wasDuplicate: true)
                        WindowManager.notifyDataChanged()

                    case .ready(let entryId, _):
                        let entry = try? env.entries.entry(id: entryId)
                        let summary = entry.map {
                            Self.summarize(entry: $0, text: trimmed, wasDuplicate: false, env: env)
                        } ?? trimmed
                        model.onView = { WindowManager.shared.showCaptureResult(entryId: entryId) }
                        model.phase = .resolved(entry: entry, fallback: summary, wasDuplicate: false)
                        NotificationManager.shared.postResolved(summary: summary, entryId: entryId,
                                                                wasDuplicate: false)
                        WindowManager.notifyDataChanged()
                        Task { await env.prefetcher.prefetch(id: entryId) }

                    case .pending(let entryId, _):
                        // Toast is already showing .analyzing(trimmed). Wire View and
                        // enqueue background analysis; the worker fires `entryCompleted`
                        // (via the registered handler) when done — no polling.
                        // Register the handler BEFORE enqueueing so a fast-completing
                        // worker can't fire `entryCompleted` before it exists (the
                        // event would otherwise be dropped, leaving the toast stuck).
                        model.onView = { WindowManager.shared.showCaptureResult(entryId: entryId) }
                        pendingToasts[entryId] = { [weak self] outcome in
                            guard let self, let env = self.env else { return }
                            switch outcome {
                            case .ready:
                                if let e = try? env.entries.entry(id: entryId) {
                                    let summary = Self.summarize(entry: e, text: trimmed, wasDuplicate: false, env: env)
                                    model.phase = .resolved(entry: e, fallback: summary, wasDuplicate: false)
                                    NotificationManager.shared.postResolved(summary: summary, entryId: entryId,
                                                                            wasDuplicate: false)
                                    WindowManager.notifyDataChanged()
                                    Task { await env.prefetcher.prefetch(id: entryId) }
                                }
                            case .failed:
                                model.phase = .error("Phân tích thất bại")
                            default:
                                break   // skipped: leave the toast as-is
                            }
                        }
                        await env.captureWorker.enqueueAnalysis(entryId: entryId)

                    case .blocked(let behavior):
                        model.phase = .error("Daily quota reached (\(behavior.rawValue)).")

                    case .empty:
                        ToastCenter.shared.dismiss(model)
                    }
                } catch let CaptureError.quotaExceeded(behavior) {
                    model.phase = .error("Daily quota reached (\(behavior.rawValue)).")
                } catch {
                    model.phase = .error(friendly(error))
                }
            }
            ToastCenter.shared.scheduleDismiss(model, after: 6)
        }
    }

    /// Saves several list items at once (optimistic, one per line), then posts a
    /// single summary notification. Used by BatchCaptureView after the user picks.
    func captureBatch(_ items: [String], source: SourceContext) {
        guard let env else { return }
        let fallback = env.settings.defaultCaptureLanguage
        let trimmed = items.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        Task {
            // Per-line language detection (NLP) off the main actor; a long paste of
            // lines would otherwise stutter the UI.
            let prepared = await Task.detached {
                trimmed.map { (text: $0, lang: LanguageDetector.detect($0, default: fallback)) }
            }.value
            var added = 0, dupes = 0
            for item in prepared {
                do {
                    switch try env.capture.beginCapture(text: item.text, language: item.lang, source: source) {
                    case let .pending(id, _):
                        await env.captureWorker.enqueueAnalysis(entryId: id)
                        added += 1
                    case .ready:
                        added += 1
                    case .duplicate:
                        dupes += 1
                    case .paragraph, .blocked, .empty:
                        break
                    }
                } catch { }
            }
            WindowManager.notifyDataChanged()
            let body = dupes > 0
                ? L.t("Added \(added) · \(dupes) already in vokab", "Đã thêm \(added) · \(dupes) đã có")
                : L.t("Added \(added) words", "Đã thêm \(added) từ")
            NotificationManager.shared.postResolved(summary: body, entryId: nil, wasDuplicate: false)
        }
    }

    func openLibrary() { WindowManager.shared.showLibrary() }
    func openEntry(_ id: Int64) { WindowManager.shared.showLibrary(select: id) }
    func reopenExtraction() {
        guard let p = pendingParagraph else { openLibrary(); return }
        WindowManager.shared.showExtraction(items: p.items, translationVi: p.translationVi,
                                            source: p.source, language: p.language, rawText: p.rawText,
                                            failedChunks: p.failedChunks)
    }

    func openCaptureResult(_ id: Int64) { WindowManager.shared.showCaptureResult(entryId: id) }
    func openReview() { WindowManager.shared.showReview() }
    func openQuickCapture() {
        // Capture the source app NOW — the frontmost app is what the user is
        // grabbing from (the non-activating panel won't change frontmost). This
        // is the entry's "seen in" context (SPEC §4); without it every hotkey
        // capture was wrongly attributed to "Manual entry".
        let front = NSWorkspace.shared.frontmostApplication
        let sourceApp = front?.localizedName
        // If it's a browser, also record the active tab URL (Automation permission).
        let sourceURL = BrowserURL.currentURL(forBundleID: front?.bundleIdentifier)
        // Auto-grab the current selection (synthetic ⌘C) so the field is prefilled
        // without a manual copy; falls back to the clipboard when not granted.
        let grabbed = SelectionGrabber.grabSelection()
        QuickCapture.shared.show(prefill: grabbed, source: sourceApp, sourceURL: sourceURL)
    }

    private static func summary(_ result: CaptureResult, text: String, env: AppEnvironment) -> String {
        if result.type == .paragraphItem {
            return "\(result.paragraphItems.count) words found in paragraph"
        }
        if let id = result.entryId, let entry = try? env.entries.entry(id: id) {
            return summarize(entry: entry, text: text, wasDuplicate: result.wasDuplicate, env: env)
        }
        return text
    }

    /// Builds the short display string for a resolved word/phrase entry.
    private static func summarize(entry: Entry, text: String, wasDuplicate: Bool,
                                   env: AppEnvironment) -> String {
        let s = CardDecoding.summary(entry, meaningLanguage: env.settings.meaningLanguage)
        var parts = [text]
        if let cefr = s.cefr { parts.append(cefr.uppercased()) }
        if let register = registerHint(entry) { parts.append(register) }
        let base = parts.joined(separator: " — ")
        return wasDuplicate ? "\(base) (already saved)" : base
    }

    private static func registerHint(_ entry: Entry) -> String? {
        if entry.cardType == .word { return CardDecoding.word(entry)?.register }
        if entry.cardType == .phrase { return CardDecoding.phrase(entry)?.register }
        return nil
    }

    private func friendly(_ error: Error) -> String {
        switch error {
        case AgyError.timeout: return "agy timed out."
        case AgyError.binaryNotFound(let path): return "agy not found at \(path)."
        case AgyError.nonZeroExit: return "agy returned an error."
        case AgyError.decodeFailure: return "Couldn't parse agy output."
        case AgyError.outputTooLarge: return "agy returned too much output."
        default: return "\(error)"
        }
    }
}
