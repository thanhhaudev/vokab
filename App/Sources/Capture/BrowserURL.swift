import AppKit

/// Reads the active tab URL of the frontmost browser via AppleScript (needs
/// Automation permission, prompted once). Returns nil for non-browsers,
/// unsupported browsers, no window, or when permission is denied — the capture
/// then simply records no URL.
enum BrowserURL {
    private static let safari: Set<String> = [
        "com.apple.Safari", "com.apple.SafariTechnologyPreview",
    ]
    /// Chromium-family browsers all expose `active tab of front window`.
    private static let chromium: Set<String> = [
        "com.google.Chrome", "com.google.Chrome.canary", "com.google.Chrome.beta",
        "com.microsoft.edgemac", "com.brave.Browser", "com.brave.Browser.beta",
        "company.thebrowser.Browser",            // Arc
        "com.vivaldi.Vivaldi", "com.operasoftware.Opera",
    ]

    static func currentURL(forBundleID bundleID: String?) -> String? {
        guard let bundleID, let source = script(for: bundleID),
              let script = NSAppleScript(source: source) else { return nil }
        var err: NSDictionary?
        let result = script.executeAndReturnError(&err)
        guard err == nil,
              let url = result.stringValue?.trimmingCharacters(in: .whitespacesAndNewlines),
              !url.isEmpty else { return nil }
        return url
    }

    private static func script(for bundleID: String) -> String? {
        if safari.contains(bundleID) {
            return "tell application id \"\(bundleID)\" to return URL of current tab of front window"
        }
        if chromium.contains(bundleID) {
            return "tell application id \"\(bundleID)\" to return URL of active tab of front window"
        }
        return nil
    }
}
