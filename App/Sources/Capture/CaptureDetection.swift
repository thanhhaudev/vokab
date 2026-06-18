import Foundation
import VokabKit

/// Live auto-detect of capture type + language for the manual capture surfaces
/// (in-Library form, Quick Capture bar). Pure + cheap; debounced by callers.
/// Language delegates to `LanguageDetector` so there is one detector in the app.
enum CaptureDetection {
    static func type(_ text: String) -> CardType { InputClassifier.classify(text) }
    static func language(_ text: String, default fallback: String = "en") -> String {
        LanguageDetector.detect(text, default: fallback)
    }
}
