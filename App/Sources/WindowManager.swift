import SwiftUI
import AppKit
import VokabKit

/// Opens and reuses the Library and Review windows from any context (menubar,
/// notification action, Services). Using AppKit-managed windows avoids the
/// `openWindow`-needs-a-live-scene limitation for a menubar agent.
///
/// A pure `.accessory` app cannot reliably bring a window to the front, so while
/// any vokab window is open the app switches to `.regular` (Dock icon appears),
/// reverting to `.accessory` once the last window closes.
@MainActor
final class WindowManager: NSObject, NSWindowDelegate {
    static let shared = WindowManager()
    var env: AppEnvironment?

    /// Posted when library/menubar data should refresh (after capture or grade).
    static let dataDidChange = Notification.Name("vokab.dataDidChange")
    static func notifyDataChanged() {
        NotificationCenter.default.post(name: dataDidChange, object: nil)
    }

    /// Posted (object = entry id `Int64`) to select an entry in an already-open
    /// Library. A freshly created Library reads `pendingSelectionId` on appear.
    static let selectEntry = Notification.Name("vokab.selectEntry")

    private var library: NSWindow?
    private var review: NSWindow?
    private var extraction: NSWindow?
    private var batch: NSWindow?
    private var captureResult: NSWindow?
    /// Entry to select when a newly created Library window first appears.
    private(set) var pendingSelectionId: Int64?

    /// Opens the Library, optionally selecting a specific entry's detail.
    func showLibrary(select entryId: Int64? = nil) {
        guard let env else { return }
        let isNew = (library == nil)
        if isNew {
            pendingSelectionId = entryId   // consumed by LibraryView on first appear
            library = makeWindow(title: "vokab", width: 1060, height: 640,
                                 minWidth: 880, minHeight: 460,
                                 root: LibraryView(env: env).environmentObject(env))
        }
        present(library)
        Self.notifyDataChanged()
        // Existing window: its view is already mounted, so notify it directly.
        if !isNew, let entryId {
            NotificationCenter.default.post(name: Self.selectEntry, object: entryId)
        }
    }

    /// Returns and clears the pending selection (called by a fresh LibraryView).
    func consumePendingSelection() -> Int64? {
        defer { pendingSelectionId = nil }
        return pendingSelectionId
    }

    func showReview() {
        guard let env else { return }
        // Recreate so the session reloads the current due cards.
        review = makeWindow(title: "Review", width: 480, height: 440,
                            minWidth: 440, minHeight: 400,
                            root: FlashcardView(env: env).environmentObject(env))
        present(review)
    }

    /// Closes the review window (the finished-screen "Done" button).
    func closeReview() { review?.close() }

    /// Opens the standalone capture-result window (mockups #1/#2) for a word or
    /// phrase entry. Reuses a single window: a later capture replaces its content
    /// rather than stacking windows.
    func showCaptureResult(entryId: Int64) {
        guard let env, let entry = try? env.entries.entry(id: entryId) else { return }
        let onDone: () -> Void = { [weak self] in self?.captureResult?.close() }
        let root = captureRoot(entry: entry, env: env, onDone: onDone)
        if captureResult == nil {
            captureResult = makeWindow(title: "vokab", width: 560, height: 620,
                                       minWidth: 480, minHeight: 420, root: root)
        } else {
            captureResult?.contentViewController =
                NSHostingController(rootView: root.frame(minWidth: 480, minHeight: 420))
            captureResult?.setContentSize(NSSize(width: 560, height: 620))
        }
        present(captureResult)
    }

    @ViewBuilder
    private func captureRoot(entry: Entry, env: AppEnvironment,
                             onDone: @escaping () -> Void) -> some View {
        switch entry.cardType {
        case .phrase:
            PhraseDetailView(entry: entry, context: .capture(onDone: onDone)).environmentObject(env)
        default:
            WordDetailView(entry: entry, context: .capture(onDone: onDone)).environmentObject(env)
        }
    }

    func showExtraction(items: [ParagraphItem], translationVi: String? = nil, source: SourceContext, language: String, rawText: String) {
        guard let env else { return }
        let root = ParagraphExtractionView(items: items, translationVi: translationVi,
                                           source: source, language: language,
                                           rawText: rawText,
                                           onClose: { [weak self] in self?.extraction?.close() })
            .environmentObject(env)
        extraction = makeWindow(title: "Extract vocabulary", width: 640, height: 620,
                                minWidth: 520, minHeight: 420, root: root)
        present(extraction)
    }

    func showBatch(lines: [String], source: SourceContext) {
        guard let env else { return }
        let root = BatchCaptureView(lines: lines, source: source,
                                    onClose: { [weak self] in self?.batch?.close() })
            .environmentObject(env)
        batch = makeWindow(title: "Save to library", width: 560, height: 500,
                           minWidth: 480, minHeight: 360, root: root)
        present(batch)
    }

    private func makeWindow<V: View>(title: String, width: CGFloat, height: CGFloat,
                                     minWidth: CGFloat, minHeight: CGFloat, root: V) -> NSWindow {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: width, height: height),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered, defer: false)
        window.title = title
        let hosting = NSHostingController(
            rootView: root.frame(minWidth: minWidth, minHeight: minHeight))
        window.contentViewController = hosting
        // contentViewController resizes the window to the view's fitting size;
        // restore the intended content size and pin a sensible minimum.
        window.setContentSize(NSSize(width: width, height: height))
        window.contentMinSize = NSSize(width: minWidth, height: minHeight)
        window.isReleasedWhenClosed = false
        window.delegate = self
        window.center()
        return window
    }

    private func present(_ window: NSWindow?) {
        guard let window else { return }
        NSApp.setActivationPolicy(.regular)        // ensure the window can come forward
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
        window.orderFrontRegardless()
    }

    // MARK: NSWindowDelegate

    func windowWillClose(_ notification: Notification) {
        // After the closing window goes away, drop back to a menubar agent if no
        // vokab windows remain visible.
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            let stillVisible = [self.library, self.review, self.captureResult, self.extraction, self.batch]
                .compactMap { $0 }
                .contains { $0.isVisible }
            if !stillVisible {
                NSApp.setActivationPolicy(.accessory)
            }
        }
    }
}
