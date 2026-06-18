import AppKit
import VokabKit

/// Handles the macOS Services menu item "Capture to vokab" (SPEC §6). The
/// declaration lives in Info.plist (NSServices); this object is the receiver.
final class ServicesProvider: NSObject {
    static let shared = ServicesProvider()
    private weak var env: AppEnvironment?

    @MainActor
    func register(env: AppEnvironment?) {
        self.env = env
        NSApp.servicesProvider = self
        NSUpdateDynamicServices()
    }

    /// NSServices entry point (referenced by NSMessage = "captureToVokab").
    @objc func captureToVokab(_ pasteboard: NSPasteboard, userData: String?,
                              error: AutoreleasingUnsafeMutablePointer<NSString>) {
        guard let text = pasteboard.string(forType: .string), !text.isEmpty else {
            error.pointee = "No text to capture." as NSString
            return
        }
        Task { @MainActor in
            CaptureController.shared.capture(text)
        }
    }

    /// NSServices entry point for "Capture to vokab (with context)" — forces the
    /// selection through paragraph extraction so the highlighted sentence is kept
    /// as each chosen word's source context (referenced by NSMessage).
    @objc func captureWithContextToVokab(_ pasteboard: NSPasteboard, userData: String?,
                                         error: AutoreleasingUnsafeMutablePointer<NSString>) {
        guard let text = pasteboard.string(forType: .string), !text.isEmpty else {
            error.pointee = "No text to capture." as NSString
            return
        }
        Task { @MainActor in
            CaptureController.shared.capture(text, type: .paragraphItem)
        }
    }
}
