import Foundation

/// Splits a long paragraph into sentence-aligned chunks so each agy extraction
/// call sees a digestible amount of text (SPEC §7c, paragraph fixes). Splitting
/// on sentences (never mid-sentence) keeps each word's context intact.
public enum ParagraphChunker {
    /// Greedily groups whole sentences into chunks of at most `maxWords` words.
    /// A sentence longer than `maxWords` becomes its own (oversized) chunk rather
    /// than being split. Text at or under `maxWords` returns a single chunk;
    /// blank text returns no chunks.
    public static func chunk(_ text: String, maxWords: Int = 120) -> [String] {
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return [] }
        if wordCount(text) <= maxWords { return [text] }

        var chunks: [String] = []
        var current = ""
        var currentWords = 0
        for sentence in SentenceExtractor.sentences(in: text) {
            let w = wordCount(sentence)
            if currentWords > 0 && currentWords + w > maxWords {
                chunks.append(current)
                current = ""
                currentWords = 0
            }
            current += sentence
            currentWords += w
        }
        if !current.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            chunks.append(current)
        }
        return chunks
    }

    private static func wordCount(_ s: String) -> Int {
        s.split { $0 == " " || $0 == "\n" || $0 == "\t" }.count
    }
}
