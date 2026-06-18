import Foundation

/// Derive một group key ổn định từ payload (prefix bucketId, fallback slug displayName).
public enum AntigravityQuotaGroupKey {
    public static func derive(group: AntigravityQuotaSummary.Group) -> String {
        if let id = group.buckets.first?.bucketId, !id.isEmpty {
            if let dash = id.firstIndex(of: "-") { return String(id[..<dash]).lowercased() }
            return id.lowercased()
        }
        let slug = (group.displayName ?? "group").lowercased()
            .replacingOccurrences(of: " ", with: "-")
            .filter { $0.isLetter || $0.isNumber || $0 == "-" }
        return slug.isEmpty ? "group" : slug
    }
}

/// Map tên model (display string của `agy models`, lưu ở `VokabSettings.model`) → group key.
public enum AntigravityModelGroup {
    /// Trả nil nếu model nil/không nhận diện được → caller hiển thị nhóm most-constrained + nhãn "default".
    public static func groupKey(forModel model: String?) -> String? {
        guard let m = model?.trimmingCharacters(in: .whitespaces), !m.isEmpty else { return nil }
        let lower = m.lowercased()
        if lower.hasPrefix("gemini") { return "gemini" }
        if lower.hasPrefix("claude") || lower.hasPrefix("opus") || lower.hasPrefix("sonnet")
            || lower.hasPrefix("haiku") || lower.hasPrefix("gpt") || lower.hasPrefix("fable") { return "3p" }
        return nil
    }
}
