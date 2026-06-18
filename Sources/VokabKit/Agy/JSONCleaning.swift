import Foundation

/// Utilities for turning raw `agy` stdout into decodable JSON.
///
/// agy is instructed to return pure JSON, but as an LLM it may occasionally
/// wrap output in a markdown code fence or add a stray preamble. These helpers
/// defensively recover the JSON payload before decoding (SPEC §10).
public enum JSONCleaning {

    /// Strips markdown code fences and any surrounding prose, returning the
    /// substring from the first `{`/`[` to the matching last `}`/`]`.
    ///
    /// Plain JSON is returned trimmed but otherwise unchanged.
    public static func stripJSONFences(_ raw: String) -> String {
        var text = raw.trimmingCharacters(in: .whitespacesAndNewlines)

        // Remove a leading ```json / ``` fence and a trailing ``` fence.
        if text.hasPrefix("```") {
            // Drop the first line (``` or ```json).
            if let firstNewline = text.firstIndex(of: "\n") {
                text = String(text[text.index(after: firstNewline)...])
            } else {
                text = String(text.drop(while: { $0 == "`" }))
            }
            // Drop a trailing fence.
            if let fenceRange = text.range(of: "```", options: .backwards) {
                text = String(text[..<fenceRange.lowerBound])
            }
            text = text.trimmingCharacters(in: .whitespacesAndNewlines)
        }

        // Narrow to the outermost JSON object/array if there is surrounding prose.
        let firstObject = text.firstIndex(of: "{")
        let firstArray = text.firstIndex(of: "[")
        let start: String.Index?
        switch (firstObject, firstArray) {
        case let (.some(o), .some(a)): start = min(o, a)
        case let (.some(o), .none): start = o
        case let (.none, .some(a)): start = a
        default: start = nil
        }

        guard let start else { return text }

        let isObject = text[start] == "{"
        let closing: Character = isObject ? "}" : "]"
        guard let end = text.lastIndex(of: closing), end >= start else { return text }

        return String(text[start...end])
    }

    /// A JSONDecoder configured to map agy's snake_case keys to the camelCase
    /// properties on the card models.
    public static func makeDecoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        return decoder
    }

    /// Cleans then decodes `raw` agy output into `T`. Throws `AgyError.decodeFailure`
    /// (carrying the raw text) on failure.
    public static func decode<T: Decodable>(_ type: T.Type, from raw: String) throws -> T {
        let cleaned = stripJSONFences(raw)
        guard let data = cleaned.data(using: .utf8) else {
            throw AgyError.decodeFailure(raw: raw)
        }
        do {
            return try makeDecoder().decode(T.self, from: data)
        } catch {
            throw AgyError.decodeFailure(raw: raw)
        }
    }
}
