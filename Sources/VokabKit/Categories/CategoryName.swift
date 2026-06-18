import Foundation

/// Chuẩn hoá tên category để HIỂN THỊ: snake_case/kebab-case → "Title-ish"
/// (hoa chữ cái đầu, phần còn lại giữ nguyên). KHÔNG dùng cho dedup —
/// dedup vẫn qua `TextKey.normalize`.
public enum CategoryName {
    public static func prettify(_ raw: String) -> String {
        let spaced = raw
            .replacingOccurrences(of: "_", with: " ")
            .replacingOccurrences(of: "-", with: " ")
            .split(whereSeparator: { $0 == " " || $0 == "\t" || $0 == "\n" })
            .joined(separator: " ")
        guard !spaced.isEmpty else { return "" }
        return spaced.prefix(1).uppercased() + spaced.dropFirst()
    }
}
