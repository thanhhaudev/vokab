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
        MenuBarExtra {
            MenubarPopoverView().environmentObject(env)
        } label: {
            // One image (V, or V + amber dot when analyzing). MenuBarExtra clips a
            // multi-view label to one icon slot, so the dot must live inside the image.
            Image(nsImage: env.activeAnalyses > 0 ? MenubarIcon.processing(pulse: env.pulse) : MenubarIcon.idle())
        }
        .menuBarExtraStyle(.window)

        Settings {
            SettingsView().environmentObject(env)
        }
    }
}
