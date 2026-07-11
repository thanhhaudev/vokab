import SwiftUI

/// vokab menubar agent entry point.
///
/// Runs as an `LSUIElement` accessory (no Dock icon). The menubar status item and
/// its popover are owned by `StatusItemController` (AppKit), wired in `AppDelegate`
/// — not a `MenuBarExtra` scene, so the activity dot can be a separate amber layer
/// over a template V (per-screen tinting). Library and Review windows are opened on
/// demand by `WindowManager` (AppKit-managed). The Settings scene hosts the AI Engine tab.
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
        // The menubar status item lives in StatusItemController (see AppDelegate);
        // this scene only hosts Settings. `env` is created here and shared via
        // `AppEnvironment.shared`, which is what the status item's popover uses.
        Settings {
            SettingsView().environmentObject(env)
        }
        .commands {
            // Swap the OS-standard about panel for AboutView (WindowManager.showAbout),
            // which carries a GitHub link the generic AppKit panel has no room for.
            CommandGroup(replacing: .appInfo) {
                Button(L.t("About vokab", "Giới thiệu vokab")) {
                    WindowManager.shared.showAbout()
                }
            }
        }
    }
}
