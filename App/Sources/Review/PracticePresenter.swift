import SwiftUI
import AppKit
import VokabKit

/// Opens the production (writing) card for a single entry on demand — used by the
/// "Practice writing" affordance in the word detail. Independent of a full review
/// session.
@MainActor
final class PracticePresenter {
    static let shared = PracticePresenter()
    private var window: NSWindow?

    func present(entry: Entry) {
        guard let env = AppEnvironment.shared, let id = entry.id else { return }
        let state = (try? env.review.state(entryId: id))
            ?? ReviewState(entryId: id, dueDate: Date())
        let card = ReviewCard(entry: entry, state: state)

        let root = ProductionCardView(env: env, card: card) { [weak self] grade in
            let now = Date()
            let updated = SM2.schedule(state, grade: grade, now: now)
            try? env.review.update(updated)
            try? env.reviewLog.record(on: now)
            WindowManager.notifyDataChanged()
            self?.window?.close()
        }
        .frame(width: 460, height: 420)
        .background(Theme.bgPrimary)

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 460, height: 420),
            styleMask: [.titled, .closable], backing: .buffered, defer: false)
        window.title = "Practice"
        window.contentViewController = NSHostingController(rootView: root)
        window.setContentSize(NSSize(width: 460, height: 420))
        window.isReleasedWhenClosed = false
        window.center()
        self.window = window
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
    }
}
