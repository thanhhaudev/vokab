import AppKit
import Combine
import SwiftUI

/// Owns the menubar status item and its popover (SPEC §tech-stack: NSStatusItem +
/// NSPopover). Replaces the former `MenuBarExtra` scene so the activity indicator
/// can be a separate amber view over a **template** V glyph — letting macOS tint
/// the V per-screen (white on the active menubar, dimmed elsewhere) while the dot
/// keeps its amber color. A single shared `NSImage` can't be tinted per-screen, so
/// the colored dot must live outside the template image.
@MainActor
final class StatusItemController: NSObject {
    static let shared = StatusItemController()

    private var statusItem: NSStatusItem?
    private let popover = NSPopover()
    /// Amber activity dot (a subview, not a raw layer, so it follows the status
    /// button's flipped coordinate system predictably). Shown only while analyzing.
    private let dotView = NSView()
    private var cancellables = Set<AnyCancellable>()
    private var env: AppEnvironment?
    private var isProcessing = false

    private var button: NSStatusBarButton? { statusItem?.button }

    /// Builds the status item, popover, and dot view, and subscribes to the
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
            button.action = #selector(togglePopover(_:))

            dotView.wantsLayer = true
            dotView.layer?.backgroundColor = MenubarIcon.dotColor.cgColor
            dotView.layer?.cornerRadius = MenubarIcon.dotFrame.width / 2
            dotView.isHidden = true
            button.addSubview(dotView)
        }

        // Popover hosts the existing SwiftUI menubar surface unchanged.
        let host = NSHostingController(rootView: MenubarPopoverView().environmentObject(env))
        host.sizingOptions = .preferredContentSize   // popover tracks SwiftUI content size
        popover.contentViewController = host
        popover.behavior = .transient                // dismiss on outside click
        // Force aqua (non-vibrant) like the rest of the app (NSApp.appearance = .aqua).
        // Otherwise the popover's vibrant appearance makes SwiftUI's default `.primary`
        // text (e.g. due-row words, typed capture text) blend into the white background.
        popover.appearance = NSAppearance(named: .aqua)

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

    @objc private func togglePopover(_ sender: Any?) {
        guard let button else { return }
        if popover.isShown {
            popover.performClose(sender)
        } else {
            // The agent app is .accessory; activate so the capture TextField can
            // take keyboard focus, then make the popover window key.
            NSApp.activate(ignoringOtherApps: true)
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
            popover.contentViewController?.view.window?.makeKey()
        }
    }
}
