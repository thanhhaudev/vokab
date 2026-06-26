import Foundation
import VokabKit

/// Decodes the typed card out of an entry's stored `ai_result`.
enum CardDecoding {
    static func word(_ entry: Entry) -> WordCard? {
        try? JSONCleaning.decode(WordCard.self, from: entry.aiResult)
    }
    static func phrase(_ entry: Entry) -> PhraseCard? {
        try? JSONCleaning.decode(PhraseCard.self, from: entry.aiResult)
    }
    static func paragraphItem(_ entry: Entry) -> ParagraphItem? {
        try? JSONCleaning.decode(ParagraphItem.self, from: entry.aiResult)
    }

    /// A compact summary used in list rows: part-of-speech, a primary meaning,
    /// and CEFR — regardless of card type.
    static func summary(_ entry: Entry, meaningLanguage: String) -> (pos: String?, meaning: String?, cefr: String?) {
        switch entry.cardType {
        case .word:
            let c = word(entry)
            return (c?.combinedPOS, c?.meaning(forLanguage: meaningLanguage), c?.cefrLevel ?? entry.cefr)
        case .phrase:
            let c = phrase(entry)
            return (c?.type, c?.meaning(forLanguage: meaningLanguage), c?.cefrLevel ?? entry.cefr)
        case .paragraphItem:
            let c = paragraphItem(entry)
            return (c?.pos, c?.meaning, c?.cefr ?? entry.cefr)
        case .none:
            return (nil, nil, entry.cefr)
        }
    }
}
