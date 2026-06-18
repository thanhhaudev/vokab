import Foundation
import NaturalLanguage

/// Detect ngôn ngữ capture (best-effort) với 3 lớp:
/// 1) heuristic từ đơn (ASCII→en, dấu tiếng Việt→vi) — chính xác cho input ngắn,
/// 2) NLLanguageRecognizer RÀNG BUỘC tập `allowed` + ngưỡng confidence,
/// 3) fallback `default` khi không chắc.
public enum LanguageDetector {
    private static let vietnameseScalars: Set<Character> = Set(
        "ăâđêôơưàáạảãằắặẳẵầấậẩẫèéẹẻẽềếệểễìíịỉĩòóọỏõồốộổỗờớợởỡùúụủũừứựửữỳýỵỷỹ"
        + "ĂÂĐÊÔƠƯÀÁẠẢÃẰẮẶẲẴẦẤẬẨẪÈÉẸẺẼỀẾỆỂỄÌÍỊỈĨÒÓỌỎÕỒỐỘỔỖỜỚỢỞỠÙÚỤỦŨỪỨỰỬỮỲÝỴỶỸ")

    public static func hasVietnameseDiacritics(_ s: String) -> Bool {
        s.contains { vietnameseScalars.contains($0) }
    }

    public static func isPlainASCIILetters(_ s: String) -> Bool {
        let letters = s.filter { !$0.isWhitespace }
        guard !letters.isEmpty else { return false }
        return letters.allSatisfy { $0.isLetter && $0.isASCII }
    }

    public static func detect(_ text: String, default defaultLanguage: String,
                              allowed: [String] = ["en", "vi"]) -> String {
        let t = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !t.isEmpty else { return defaultLanguage }

        if hasVietnameseDiacritics(t) { return "vi" }
        let wordCount = t.split(whereSeparator: { $0 == " " }).count
        if wordCount <= 2 && isPlainASCIILetters(t) { return "en" }

        let rec = NLLanguageRecognizer()
        rec.languageConstraints = allowed.map { NLLanguage($0) }
        rec.processString(t)
        let hyp = rec.languageHypotheses(withMaximum: 1)
        if let best = hyp.max(by: { $0.value < $1.value }), best.value >= 0.5 {
            return best.key.rawValue
        }
        return defaultLanguage
    }
}
