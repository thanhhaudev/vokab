import AppKit

/// Wires AppKit-level concerns at launch: accessory activation policy, capture
/// controller / window manager / notifications, and the Services provider.
final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)   // menubar agent, no Dock icon
        // The mockup is light-only; force light appearance for faithful chrome.
        NSApp.appearance = NSAppearance(named: .aqua)

        let env = AppEnvironment.shared
        if let env { StatusItemController.shared.configure(env: env) }   // menubar status item + popover
        CaptureController.shared.env = env
        WindowManager.shared.env = env
        NotificationManager.shared.env = env
        NotificationManager.shared.configure()

        ServicesProvider.shared.register(env: env)

        // Warm the agy model list (cold-starts ~7s) so Settings pickers are instant.
        if let path = env?.settings.agyPath { ModelCache.refresh(agyPath: path) }

        // Global hotkey → quick capture (opt-in).
        GlobalHotkey.shared.onTrigger = { CaptureController.shared.openQuickCapture() }
        if let s = env?.settings, s.globalHotkeyEnabled {
            GlobalHotkey.shared.register(keyCode: s.globalHotkeyKeyCode, modifiers: s.globalHotkeyModifiers)
        }
    }
}
