import Foundation
import AppKit
import VokabKit

/// Exports entries to CSV, Markdown, or Anki-importable TSV (SPEC §13).
enum ExportFormat: String, CaseIterable, Identifiable {
    case csv = "CSV"
    case markdown = "Markdown"
    case anki = "Anki (TSV)"
    var id: String { rawValue }
    var fileExtension: String {
        switch self {
        case .csv: return "csv"
        case .markdown: return "md"
        case .anki: return "txt"
        }
    }
}

enum Exporter {
    static func render(_ entries: [Entry], format: ExportFormat, meaningLanguage: String) -> String {
        switch format {
        case .csv:      return csv(entries, meaningLanguage: meaningLanguage)
        case .markdown: return markdown(entries, meaningLanguage: meaningLanguage)
        case .anki:     return anki(entries, meaningLanguage: meaningLanguage)
        }
    }

    private static func meaning(_ entry: Entry, _ lang: String) -> String {
        CardDecoding.summary(entry, meaningLanguage: lang).meaning ?? ""
    }

    /// Display category for grouping/columns; nil category falls back to "Uncategorized".
    private static func category(_ entry: Entry) -> String { entry.category ?? "Uncategorized" }

    private static func csv(_ entries: [Entry], meaningLanguage: String) -> String {
        var lines = ["text,type,language,cefr,category,meaning"]
        for e in entries {
            let cols = [e.rawText, e.type, e.language, e.cefr ?? "", category(e), meaning(e, meaningLanguage)]
            lines.append(cols.map(escapeCSV).joined(separator: ","))
        }
        return lines.joined(separator: "\n")
    }

    private static func markdown(_ entries: [Entry], meaningLanguage: String) -> String {
        var lines = ["| Word | Type | CEFR | Category | Meaning |", "|---|---|---|---|---|"]
        for e in entries {
            // Every user-derived cell must escape `|` (column separator) and
            // newlines (would split the row) — including rawText, not just meaning.
            let cols = [e.rawText, e.type, e.cefr?.uppercased() ?? "", category(e), meaning(e, meaningLanguage)]
                .map(escapeMarkdown)
            lines.append("| \(cols.joined(separator: " | ")) |")
        }
        return lines.joined(separator: "\n")
    }

    /// Anki TSV with a per-row deck column. `#deck column:3` maps each category to
    /// its own deck on import (SPEC §7: export by category).
    private static func anki(_ entries: [Entry], meaningLanguage: String) -> String {
        var lines = ["#separator:tab", "#deck column:3", "#html:true"]
        for e in entries {
            // Tabs (field separator) and newlines (record separator) in any field
            // would corrupt the import — sanitize every column.
            let cols = [e.rawText, meaning(e, meaningLanguage), "vokab::\(category(e))"].map(escapeAnki)
            lines.append(cols.joined(separator: "\t"))
        }
        return lines.joined(separator: "\n")
    }

    private static func escapeCSV(_ field: String) -> String {
        if field.contains(",") || field.contains("\"") || field.contains("\n") {
            return "\"\(field.replacingOccurrences(of: "\"", with: "\"\""))\""
        }
        return field
    }

    /// Escapes a Markdown table cell: `|` is the column delimiter and any newline
    /// would break the row, so both are neutralized (newline → `<br>`).
    private static func escapeMarkdown(_ field: String) -> String {
        field.replacingOccurrences(of: "|", with: "\\|")
             .replacingOccurrences(of: "\r\n", with: "<br>")
             .replacingOccurrences(of: "\n", with: "<br>")
             .replacingOccurrences(of: "\r", with: "<br>")
    }

    /// Escapes an Anki TSV field: tab is the field delimiter and newline the record
    /// delimiter. Anki renders HTML (`#html:true`), so newline → `<br>`, tab → space.
    private static func escapeAnki(_ field: String) -> String {
        field.replacingOccurrences(of: "\t", with: " ")
             .replacingOccurrences(of: "\r\n", with: "<br>")
             .replacingOccurrences(of: "\n", with: "<br>")
             .replacingOccurrences(of: "\r", with: "<br>")
    }

    /// Shows a save panel and writes the rendered export.
    @MainActor
    static func presentSavePanel(_ entries: [Entry], format: ExportFormat, meaningLanguage: String) {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = "vokab-export.\(format.fileExtension)"
        panel.canCreateDirectories = true
        guard panel.runModal() == .OK, let url = panel.url else { return }
        let content = render(entries, format: format, meaningLanguage: meaningLanguage)
        try? content.data(using: .utf8)?.write(to: url)
    }
}
