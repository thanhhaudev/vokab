import SwiftUI

/// vokab menubar agent entry point.
///
/// Runs as an `LSUIElement` accessory (no Dock icon). The UI lives in a
/// `MenuBarExtra` popover; Library and Review windows are opened on demand by
/// `WindowManager` (AppKit-managed). The Settings scene hosts the AI Engine tab.
@main
struct VokabApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var env: AppEnvironment

    init() {
        // Headless verification hook: may print counts and exit before any UI.
        AppEnvironment.runSelfTestIfRequested()
        L.lang = SettingsStore.load().appLanguage
        _env = StateObject(wrappedValue: AppEnvironment.makeResilient())
    }

    var body: some Scene {
        MenuBarExtra("vokab", systemImage: "character.book.closed.fill") {
            MenubarPopoverView().environmentObject(env)
        }
        .menuBarExtraStyle(.window)

        Settings {
            SettingsView().environmentObject(env)
        }
    }
}
