import AppKit
import ApplicationServices
import CoreGraphics

/// Grabs the current selection from the frontmost app by synthesizing ⌘C, so
/// Quick Capture can prefill without the user pressing ⌘C themselves. The user's
/// clipboard is snapshotted and restored around the synthetic copy.
///
/// Requires Accessibility permission to post the key event (System Settings →
/// Privacy & Security → Accessibility). Without it, returns nil and the caller
/// falls back to reading whatever is already on the clipboard. This deliberately
/// relaxes the original "no Accessibility" non-goal (user opted in, 2026-06-17).
@MainActor
enum SelectionGrabber {

    static var isTrusted: Bool { AXIsProcessTrusted() }

    /// The freshly-selected text, or nil if nothing was selected or Accessibility
    /// isn't granted. Does NOT prompt — the system dialog would steal focus from
    /// Quick Capture. Permission is requested deliberately from Settings instead.
    static func grabSelection() -> String? {
        guard AXIsProcessTrusted() else { return nil }

        let pb = NSPasteboard.general
        // Snapshot the clipboard so we can restore it after the synthetic copy.
        let saved: [NSPasteboardItem] = (pb.pasteboardItems ?? []).map { item in
            let copy = NSPasteboardItem()
            for type in item.types {
                if let data = item.data(forType: type) { copy.setData(data, forType: type) }
            }
            return copy
        }
        let beforeCount = pb.changeCount

        synthesizeCmdC()

        // Wait briefly for the target app to place its selection on the clipboard.
        var waitedMs = 0
        while pb.changeCount == beforeCount && waitedMs < 250 {
            usleep(10_000)   // 10 ms
            waitedMs += 10
        }

        // Only treat it as a real selection if a fresh copy actually landed.
        let grabbed = (pb.changeCount != beforeCount) ? pb.string(forType: .string) : nil

        // Restore the user's original clipboard.
        pb.clearContents()
        if !saved.isEmpty { pb.writeObjects(saved) }

        let trimmed = grabbed?.trimmingCharacters(in: .whitespacesAndNewlines)
        return (trimmed?.isEmpty == false) ? trimmed : nil
    }

    /// Shows the system Accessibility prompt if not yet trusted. Call only from a
    /// deliberate UI action (e.g. enabling the hotkey in Settings) — never during
    /// capture, since the dialog steals focus from Quick Capture. After prompting,
    /// it watches for the grant and relaunches the app (an ad-hoc build won't pick
    /// up the new permission live).
    @discardableResult
    static func requestAccessibility() -> Bool {
        if AXIsProcessTrusted() { return true }
        let key = kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String
        let trusted = AXIsProcessTrustedWithOptions([key: true] as CFDictionary)
        if !trusted { scheduleGrantCheck(0) }
        return trusted
    }

    /// Polls (~1 s, up to 3 min) until Accessibility is granted, then relaunches.
    private static func scheduleGrantCheck(_ elapsed: Double) {
        guard elapsed < 180 else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
            MainActor.assumeIsolated {
                if AXIsProcessTrusted() { relaunch() }
                else { scheduleGrantCheck(elapsed + 1.0) }
            }
        }
    }

    /// Restarts the app: a detached shell waits for this process to exit, then
    /// reopens the bundle, so the freshly-granted permission takes effect.
    static func relaunch() {
        let pid = ProcessInfo.processInfo.processIdentifier
        let path = Bundle.main.bundlePath
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/bin/sh")
        task.arguments = ["-c", "while kill -0 \(pid) 2>/dev/null; do sleep 0.2; done; open \"\(path)\""]
        try? task.run()
        NSApp.terminate(nil)
    }

    private static func synthesizeCmdC() {
        let src = CGEventSource(stateID: .combinedSessionState)
        let cKey: CGKeyCode = 0x08   // kVK_ANSI_C
        let down = CGEvent(keyboardEventSource: src, virtualKey: cKey, keyDown: true)
        down?.flags = .maskCommand
        let up = CGEvent(keyboardEventSource: src, virtualKey: cKey, keyDown: false)
        up?.flags = .maskCommand
        down?.post(tap: .cghidEventTap)
        up?.post(tap: .cghidEventTap)
    }
}
