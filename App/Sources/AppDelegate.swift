import AppKit
import VokabKit

/// Single source of truth for applying the appearance preference.
enum AppearanceController {
    static func apply(_ mode: AppearanceMode) {
        switch mode {
        case .system: NSApp.appearance = nil                              // follow macOS
        case .light:  NSApp.appearance = NSAppearance(named: .aqua)
        case .dark:   NSApp.appearance = NSAppearance(named: .darkAqua)
        }
    }
}

/// Wires AppKit-level concerns at launch: accessory activation policy, capture
/// controller / window manager / notifications, and the Services provider.
final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)   // menubar agent, no Dock icon

        let env = AppEnvironment.shared
        AppearanceController.apply(env?.settings.appearanceMode ?? .system)
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
