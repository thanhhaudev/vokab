import Foundation

/// Minimal two-language string helper. Default English; "vi" uses the mockup's
/// Vietnamese wording. The active language is set at launch from settings and
/// updated when the user changes it (chrome fully applies on relaunch).
enum L {
    /// "en" (default) or "vi".
    static var lang: String = "en"

    /// Returns the English or Vietnamese variant for the current app language.
    static func t(_ en: String, _ vi: String) -> String {
        lang == "vi" ? vi : en
    }
}
