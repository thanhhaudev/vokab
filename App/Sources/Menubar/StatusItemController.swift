import AppKit
import Combine
import SwiftUI

/// A borderless, non-activating panel that can still become key so a `TextField`
/// inside it receives keystrokes **without activating the whole app**. This is what
/// lets the menubar surface accept typed input while leaving other vokab windows
/// (possibly on another screen/Space) untouched — avoiding the cross-screen focus
/// steal that `NSApp.activate(ignoringOtherApps:)` caused with the old `NSPopover`.
private final class MenubarPanel: NSPanel {
    /// Invoked on Esc (cancelOperation) so the controller can tear down monitors.
    var onCancel: (() -> Void)?
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
    override func cancelOperation(_ sender: Any?) { onCancel?() }
}

/// SwiftUI wrapper for the panel content. Rounds the corners in SwiftUI (so the
/// borderless window's shadow follows the rounded shape without touching the
/// hosting view's layer) and reports its measured size up via `onGeometryChange`
/// — a pure measurement that installs **no Auto Layout constraints**, so the
/// constraint solver never runs and can't recurse (the cause of the earlier crash).
private struct MenubarPanelContent: View {
    let env: AppEnvironment
    let onSize: (CGSize) -> Void
    var body: some View {
        MenubarPopoverView()
            .environmentObject(env)
            .clipShape(RoundedRectangle(cornerRadius: Theme.radiusLg, style: .continuous))
            .onGeometryChange(for: CGSize.self) { $0.size } action: { onSize($0) }
    }
}

/// Owns the menubar status item and its panel (SPEC §tech-stack: NSStatusItem).
/// The activity indicator is a separate amber view over a **template** V glyph —
/// letting macOS tint the V per-screen (white on the active menubar, dimmed
/// elsewhere) while the dot keeps its amber color. A single shared `NSImage` can't
/// be tinted per-screen, so the colored dot must live outside the template image.
///
/// The popover surface is a custom borderless `MenubarPanel` rather than `NSPopover`
/// so it has **no tail** (off-design) and needs **no app activation** to type into
/// the capture field (no cross-screen focus steal). Sizing is driven manually from
/// the hosting controller's `preferredContentSize` (NOT by binding the controller as
/// the window's `contentViewController`, which would fight a manual `setFrame` and
/// send the autolayout engine into infinite recursion).
@MainActor
final class StatusItemController: NSObject {
    static let shared = StatusItemController()

    private var statusItem: NSStatusItem?
    private var panel: MenubarPanel?
    private var host: NSHostingController<AnyView>?
    /// Amber activity dot (a subview, not a raw layer, so it follows the status
    /// button's flipped coordinate system predictably). Shown only while analyzing.
    private let dotView = NSView()
    private var cancellables = Set<AnyCancellable>()
    private var env: AppEnvironment?
    private var isProcessing = false
    /// Guards `resizePanel` against the layout pass it triggers re-entering it.
    private var isResizing = false

    // Dismissal monitors (live only while the panel is shown).
    private var globalMonitor: Any?
    private var localMonitor: Any?

    // Screen-space anchor: the panel's top edge stays pinned here even as its
    // content height changes (e.g. the spell gate appearing), so it grows downward.
    private var anchorTopY: CGFloat = 0
    private var anchorOriginX: CGFloat = 0

    private var button: NSStatusBarButton? { statusItem?.button }

    /// Builds the status item, panel host, and dot view, and subscribes to the
    /// environment's activity/pulse. Idempotent: a second call is a no-op.
    func configure(env: AppEnvironment) {
        guard statusItem == nil else { return }
        self.env = env

        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem = item

        if let button = item.button {
            button.image = MenubarIcon.idle()
            button.imagePosition = .imageOnly
            button.target = self
            button.action = #selector(togglePanel(_:))

            dotView.wantsLayer = true
            dotView.layer?.backgroundColor = MenubarIcon.dotColor.cgColor
            dotView.layer?.cornerRadius = MenubarIcon.dotFrame.width / 2
            dotView.isHidden = true
            button.addSubview(dotView)
        }

        // Host the existing SwiftUI surface. We deliberately do NOT set
        // `sizingOptions` — that installs Auto Layout constraints that send the
        // constraint solver into infinite recursion in a borderless window. Size is
        // measured manually; dynamic changes arrive via the content's onGeometryChange.
        let controller = NSHostingController(
            rootView: AnyView(MenubarPanelContent(env: env) { [weak self] size in
                Task { @MainActor in self?.resizePanel(to: size) }
            }))
        host = controller

        env.$activeAnalyses
            .receive(on: RunLoop.main)
            .sink { [weak self] count in self?.setProcessing(count > 0) }
            .store(in: &cancellables)

        env.$pulse
            .receive(on: RunLoop.main)
            .sink { [weak self] pulse in self?.applyPulse(pulse) }
            .store(in: &cancellables)
    }

    /// Swaps the glyph (idle ↔ wide template V) and shows/hides the dot.
    private func setProcessing(_ processing: Bool) {
        guard processing != isProcessing else { return }
        isProcessing = processing
        button?.image = processing ? MenubarIcon.processingGlyph() : MenubarIcon.idle()
        dotView.isHidden = !processing
        if processing { layoutDot() }
    }

    /// Drives the dot's breathing alpha (and keeps it positioned as the menubar
    /// geometry can change between ticks).
    private func applyPulse(_ pulse: Double) {
        guard isProcessing else { return }
        dotView.alphaValue = CGFloat(max(0, min(1, pulse)))
        layoutDot()
    }

    /// Places the dot in the V's lower-right notch ("V."), matching the former
    /// single-image processing glyph. Anchors to the button's *actual* image rect
    /// (`imageRect(forBounds:)`) rather than assuming the image is centered, and —
    /// because `NSStatusBarButton` is flipped (y grows downward) — converts
    /// `dotFrame`'s bottom-left y into the button's top-left space.
    private func layoutDot() {
        guard let button, let cell = button.cell as? NSButtonCell else { return }
        let imageRect = cell.imageRect(forBounds: button.bounds)
        let f = MenubarIcon.dotFrame
        let y = button.isFlipped ? imageRect.minY + (imageRect.height - f.minY - f.height)
                                 : imageRect.minY + f.minY
        dotView.frame = NSRect(x: imageRect.minX + f.minX, y: y, width: f.width, height: f.height)
    }

    // MARK: Panel show / hide

    @objc private func togglePanel(_ sender: Any?) {
        if let panel, panel.isVisible { closePanel() } else { showPanel() }
    }

    /// Lazily builds the borderless panel: clear background + rounded content clip so
    /// the window shadow follows the rounded shape, no tail, inherits app appearance.
    private func makePanelIfNeeded() -> MenubarPanel? {
        if let panel { return panel }
        guard let host else { return nil }
        let p = MenubarPanel(
            contentRect: NSRect(x: 0, y: 0, width: 300, height: 200),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered, defer: false)
        p.isFloatingPanel = true
        p.level = .popUpMenu
        p.hidesOnDeactivate = false
        p.isOpaque = false
        p.backgroundColor = .clear
        p.hasShadow = true
        p.isMovable = false
        p.animationBehavior = .utilityWindow
        // Appear on whichever Space is active and float over fullscreen apps.
        p.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        p.onCancel = { [weak self] in self?.closePanel() }   // Esc

        // contentView IS the SwiftUI view. Corners are rounded inside SwiftUI
        // (MenubarPanelContent), so the window shadow follows the rounded shape
        // without manipulating the hosting view's layer.
        p.contentView = host.view

        panel = p
        return p
    }

    private func showPanel() {
        guard let button, let buttonWindow = button.window,
              let panel = makePanelIfNeeded(), let host else { return }

        // Measure the SwiftUI content (width is fixed at 300 by MenubarPopoverView).
        // Refined afterwards by the content's onGeometryChange callback if it differs.
        host.view.layoutSubtreeIfNeeded()
        let size = host.view.fittingSize

        // Anchor under the status button, on the screen the menubar click happened on.
        let rectInWindow = button.convert(button.bounds, to: nil)
        let rectOnScreen = buttonWindow.convertToScreen(rectInWindow)
        let anchorPoint = NSPoint(x: rectOnScreen.midX, y: rectOnScreen.midY)
        let screen = NSScreen.screens.first { $0.frame.contains(anchorPoint) }
            ?? buttonWindow.screen ?? NSScreen.main
        let visible = screen?.visibleFrame ?? rectOnScreen

        let gap: CGFloat = 6
        anchorTopY = rectOnScreen.minY - gap
        let edgePad: CGFloat = 8
        var x = rectOnScreen.midX - size.width / 2
        x = max(visible.minX + edgePad, min(x, visible.maxX - size.width - edgePad))
        anchorOriginX = x

        panel.setContentSize(size)
        panel.setFrameOrigin(NSPoint(x: anchorOriginX, y: anchorTopY - panel.frame.height))
        panel.makeKeyAndOrderFront(nil)
        startMonitoring()
    }

    /// Content height can change while shown (spell gate appearing/disappearing).
    /// Resize the panel and keep its top edge pinned to the menubar anchor so it
    /// grows downward, not upward. Guarded against the layout pass re-entering it.
    private func resizePanel(to size: NSSize) {
        guard let panel, panel.isVisible, !isResizing,
              size.width > 1, size.height > 1 else { return }
        // Ignore no-op reports (onGeometryChange re-fires after our own resize).
        let current = panel.frame.size
        guard abs(current.width - size.width) > 0.5 || abs(current.height - size.height) > 0.5
        else { return }
        isResizing = true
        panel.setContentSize(size)
        panel.setFrameOrigin(NSPoint(x: anchorOriginX, y: anchorTopY - panel.frame.height))
        isResizing = false
    }

    func closePanel() {
        stopMonitoring()
        guard let panel, panel.isVisible else { return }
        panel.orderOut(nil)
    }

    // MARK: Dismissal

    /// Mirrors `NSPopover.transient`: outside click / app switch / Esc dismisses.
    /// A click on the status button is *let through* so its action can toggle the
    /// panel closed (and not be re-opened by a close-then-reopen race).
    private func startMonitoring() {
        stopMonitoring()
        globalMonitor = NSEvent.addGlobalMonitorForEvents(
            matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
            self?.closePanel()
        }
        localMonitor = NSEvent.addLocalMonitorForEvents(
            matching: [.leftMouseDown, .rightMouseDown]) { [weak self] event in
            guard let self, let panel = self.panel else { return event }
            if event.window === panel { return event }              // inside the panel
            if event.window === self.button?.window { return event } // status button toggle
            self.closePanel()
            return event
        }
        NotificationCenter.default.addObserver(
            self, selector: #selector(appResignedActive),
            name: NSApplication.didResignActiveNotification, object: nil)
    }

    private func stopMonitoring() {
        if let globalMonitor { NSEvent.removeMonitor(globalMonitor) }
        if let localMonitor { NSEvent.removeMonitor(localMonitor) }
        globalMonitor = nil
        localMonitor = nil
        NotificationCenter.default.removeObserver(
            self, name: NSApplication.didResignActiveNotification, object: nil)
    }

    @objc private func appResignedActive() { closePanel() }
}
