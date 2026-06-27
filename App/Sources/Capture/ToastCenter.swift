import SwiftUI
import AppKit
import VokabKit

/// Manages a stack of capture toasts. Each capture gets its own borderless
/// `NSPanel`; they stack from the configured corner and dismiss independently,
/// re-flowing the rest. Replaces the former single-panel ToastPresenter so a new
/// capture no longer overwrites a previous toast.
@MainActor
final class ToastCenter {
    static let shared = ToastCenter()

    var corner: ToastCorner = .topTrailing

    private final class Item {
        let model: ToastModel
        let panel: NSPanel
        let hosting: NSHostingView<CaptureToastView>
        init(model: ToastModel, panel: NSPanel, hosting: NSHostingView<CaptureToastView>) {
            self.model = model; self.panel = panel; self.hosting = hosting
        }
    }

    private var items: [Item] = []
    private let maxVisible = 4
    private let width: CGFloat = 344
    private let gap: CGFloat = 10
    private let margin: CGFloat = 20

    /// Creates and shows a new toast, returning its model for the caller to drive.
    func present() -> ToastModel {
        let model = ToastModel()
        let hosting = NSHostingView(rootView: CaptureToastView(model: model))
        hosting.frame = NSRect(x: 0, y: 0, width: width, height: 120)

        let panel = NSPanel(contentRect: hosting.frame,
                            styleMask: [.borderless, .nonactivatingPanel],
                            backing: .buffered, defer: false)
        panel.isFloatingPanel = true
        panel.level = .floating
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.contentView = hosting

        let item = Item(model: model, panel: panel, hosting: hosting)
        items.append(item)

        // Re-fit + re-flow whenever this toast's content changes height.
        model.onResize = { [weak self, weak item] in
            guard let self, let item else { return }
            DispatchQueue.main.async { self.refit(item); self.relayout() }
        }

        while items.count > maxVisible {
            let old = items.removeFirst()
            old.panel.orderOut(nil)
        }

        refit(item)
        relayout()
        panel.orderFrontRegardless()
        return model
    }

    /// Shows a standalone, self-dismissing message toast (no actions) at the
    /// configured corner — for detail-screen actions like "+ add example" or
    /// reload that have no capture lifecycle to drive.
    func notice(_ text: String, danger: Bool = false, dismissAfter seconds: TimeInterval = 2.5) {
        let model = present()
        model.phase = .notice(text: text, danger: danger)
        scheduleDismiss(model, after: seconds)
    }

    func dismiss(_ model: ToastModel) {
        guard let idx = items.firstIndex(where: { $0.model === model }) else { return }
        let item = items.remove(at: idx)
        item.panel.orderOut(nil)
        relayout()
    }

    func scheduleDismiss(_ model: ToastModel, after seconds: TimeInterval) {
        DispatchQueue.main.asyncAfter(deadline: .now() + seconds) { [weak self] in
            self?.dismiss(model)
        }
    }

    private func refit(_ item: Item) {
        let fitting = item.hosting.fittingSize
        let height = max(60, fitting.height)
        item.panel.setContentSize(NSSize(width: width, height: height))
    }

    private func relayout() {
        guard let screen = NSScreen.main else { return }
        let vf = screen.visibleFrame
        let trailing = (corner == .topTrailing || corner == .bottomTrailing)
        let top = (corner == .topTrailing || corner == .topLeading)
        let x = trailing ? (vf.maxX - width - margin) : (vf.minX + margin)

        if top {
            var y = vf.maxY - margin
            for item in items.reversed() {        // newest at the top
                let h = item.panel.frame.height
                y -= h
                item.panel.setFrameOrigin(NSPoint(x: x, y: y))
                y -= gap
            }
        } else {
            var y = vf.minY + margin
            for item in items.reversed() {        // newest at the bottom
                item.panel.setFrameOrigin(NSPoint(x: x, y: y))
                y += item.panel.frame.height + gap
            }
        }
    }
}
