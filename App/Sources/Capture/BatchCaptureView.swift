import SwiftUI
import VokabKit

/// Batch-list capture (SPEC §capture): when QuickCapture receives multiple
/// non-empty lines, this dedupe-aware checklist lets the user pick which ones
/// to save, then saves each as its own entry via the optimistic capture path.
/// Mirrors ParagraphExtractionView's row/footer style.
struct BatchCaptureView: View {
    @EnvironmentObject var env: AppEnvironment
    let lines: [String]
    let source: SourceContext
    let onClose: () -> Void

    @State private var selected: Set<Int> = []
    @State private var savedSet: Set<String> = []   // normalized lines already in library

    var body: some View {
        VStack(spacing: 0) {
            header
            Hairline()
            listContent
            Hairline()
            footer
        }
        .frame(minWidth: 480, minHeight: 360)
        .background(Theme.bgPrimary)
        .onAppear { recomputeSelection() }
    }

    // MARK: Header

    private var header: some View {
        HStack {
            SecLabel(L.t("\(lines.count) items · already-saved unchecked",
                         "\(lines.count) mục · đã có thì bỏ chọn"))
            Spacer()
        }
        .padding(16)
        .background(Theme.bgSecondary)
    }

    // MARK: List

    @ViewBuilder private var listContent: some View {
        if lines.isEmpty {
            ContentUnavailableView(L.t("No items", "Không có mục nào"),
                                   systemImage: "list.bullet")
                .frame(maxHeight: .infinity)
        } else {
            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(Array(lines.enumerated()), id: \.offset) { idx, line in
                        row(idx, line)
                        Hairline()
                    }
                }
            }
        }
    }

    private func row(_ idx: Int, _ line: String) -> some View {
        let on = selected.contains(idx)
        let alreadySaved = !on && isSaved(line)
        return Button {
            if on { selected.remove(idx) } else { selected.insert(idx) }
        } label: {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: on ? "checkmark.square.fill" : "square")
                    .font(.system(size: 15)).foregroundStyle(on ? Theme.accent : Theme.textTertiary)
                    .padding(.top, 1)
                VStack(alignment: .leading, spacing: 3) {
                    Text(line)
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(alreadySaved ? Theme.textSecondary : Theme.textPrimary)
                        .lineLimit(2)
                    if alreadySaved {
                        Text(L.t("Already in library · unchecked to avoid a duplicate",
                                 "Đã có trong thư viện · bỏ chọn để tránh trùng"))
                            .font(.system(size: 12)).foregroundStyle(Theme.textTertiary)
                    }
                }
                Spacer()
            }
            .padding(.horizontal, 16).padding(.vertical, 11)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    // MARK: Footer

    private var footer: some View {
        HStack {
            Text(L.t("Selected \(selected.count) / \(lines.count)",
                     "Đã chọn \(selected.count) / \(lines.count)"))
                .font(.system(size: 12)).foregroundStyle(Theme.textTertiary)
            Spacer()
            Button(L.t("Select all", "Chọn tất cả")) { selected = Set(lines.indices) }
                .buttonStyle(.vSecondary)
            Button(L.t("Save \(selected.count) to library", "Lưu \(selected.count) vào thư viện")) { addSelected() }
                .buttonStyle(.vPrimary).disabled(selected.isEmpty)
        }
        .padding(14).background(Theme.bgSecondary)
    }

    // MARK: Logic

    private func recomputeSelection() {
        savedSet = existingSaved()
        // Default-select lines NOT already in the library (mirror paragraph dedupe).
        selected = Set(lines.indices.filter { idx in
            let key = TextKey.normalize(lines[idx])
            return !key.isEmpty && !savedSet.contains(key)
        })
    }

    private func existingSaved() -> Set<String> {
        var saved = Set<String>()
        for line in lines {
            let lang = LanguageDetector.detect(line, default: env.settings.defaultCaptureLanguage)
            if (try? env.entries.find(rawText: line, language: lang)) != nil {
                saved.insert(TextKey.normalize(line))
            }
        }
        return saved
    }

    private func isSaved(_ line: String) -> Bool {
        savedSet.contains(TextKey.normalize(line))
    }

    private func addSelected() {
        let selectedLines = selected.sorted().map { lines[$0] }
        CaptureController.shared.captureBatch(selectedLines, source: source)
        onClose()
    }
}
