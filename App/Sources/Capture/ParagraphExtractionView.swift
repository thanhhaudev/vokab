import SwiftUI
import VokabKit

/// Paragraph extraction (SPEC §12 surface #3, mockup #3): the captured paragraph
/// shown with candidate words highlighted, a Min-level filter that re-runs agy,
/// and a dedupe-aware checklist with "Add N to deck". Persists chosen items.
struct ParagraphExtractionView: View {
    @EnvironmentObject var env: AppEnvironment
    let source: SourceContext
    let language: String
    let rawText: String
    let onClose: () -> Void

    @State private var items: [ParagraphItem]
    @State private var selected: Set<Int> = []
    @State private var savedSet: Set<String> = []     // normalized words already in library
    @State private var minLevel: CEFR = .b1
    @State private var working = false
    @State private var errorText: String?

    init(items: [ParagraphItem], source: SourceContext, language: String,
         rawText: String, onClose: @escaping () -> Void) {
        _items = State(initialValue: items)
        self.source = source
        self.language = language
        self.rawText = rawText
        self.onClose = onClose
    }

    var body: some View {
        VStack(spacing: 0) {
            sourceBlock
            Hairline()
            filterBar
            if let errorText { errorBanner(errorText) }
            Hairline()
            listContent
            Hairline()
            footer
        }
        .frame(minWidth: 520, minHeight: 420)
        .background(Theme.bgPrimary)
        .overlay { if working { loadingOverlay } }
        .onAppear {
            minLevel = env.settings.minParagraphLevel
            recomputeSelection()
        }
    }

    // MARK: Source block (highlighted paragraph)

    private var sourceBlock: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                SecLabel("Source")
                Spacer()
                Text(L.t("\(wordCount) words", "\(wordCount) từ"))
                    .font(.system(size: 11)).foregroundStyle(Theme.textTertiary)
            }
            highlightedText.font(.system(size: 13)).lineSpacing(4)
        }
        .padding(16).frame(maxWidth: .infinity, alignment: .leading)
    }

    private var highlightedText: Text {
        var attr = AttributedString()
        let candidates = items.compactMap { $0.word }
        for seg in ParagraphHighlighter.segments(source: rawText, candidates: candidates) {
            var run = AttributedString(seg.text)
            if seg.isHighlight {
                run.backgroundColor = Theme.highlightBg
                run.foregroundColor = Theme.highlightText
            } else {
                run.foregroundColor = Theme.textSecondary
            }
            attr.append(run)
        }
        return Text(attr)
    }

    private var wordCount: Int {
        rawText.split(whereSeparator: { $0 == " " || $0 == "\n" || $0 == "\t" }).count
    }

    // MARK: Filter bar + Min level

    private var filterBar: some View {
        HStack(spacing: 8) {
            Image(systemName: "line.3.horizontal.decrease.circle")
                .font(.system(size: 13)).foregroundStyle(Theme.textTertiary)
            Text(L.t("\(items.count) worth learning · basic words (A1–A2) filtered out",
                     "\(items.count) từ đáng học · đã lọc bỏ từ cơ bản (A1–A2)"))
                .font(.system(size: 12)).foregroundStyle(Theme.textSecondary)
            Spacer()
            Menu {
                ForEach(CEFR.allCases, id: \.self) { lvl in
                    Button(lvl.rawValue.uppercased()) { changeMinLevel(lvl) }
                }
            } label: {
                HStack(spacing: 3) {
                    Text(L.t("Min level: \(minLevel.rawValue.uppercased())",
                             "Mức tối thiểu: \(minLevel.rawValue.uppercased())"))
                    Image(systemName: "chevron.down").font(.system(size: 10))
                }
                .font(.system(size: 12)).foregroundStyle(Theme.accent)
            }
            .menuStyle(.borderlessButton).fixedSize()
            .disabled(working)
        }
        .padding(.horizontal, 16).padding(.vertical, 8).background(Theme.bgSecondary)
    }

    private func errorBanner(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 12)).foregroundStyle(Theme.textDanger)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 16).padding(.vertical, 8)
            .background(Theme.bgDanger)
    }

    private var loadingOverlay: some View {
        ZStack {
            Color.black.opacity(0.04)
            ProgressView().controlSize(.large)
        }
    }

    // MARK: List

    @ViewBuilder private var listContent: some View {
        if items.isEmpty {
            ContentUnavailableView(L.t("No vocabulary found", "Không có từ nào"),
                                   systemImage: "text.magnifyingglass")
                .frame(maxHeight: .infinity)
        } else {
            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(Array(items.enumerated()), id: \.offset) { idx, item in
                        row(idx, item)
                        Hairline()
                    }
                }
            }
        }
    }

    private func row(_ idx: Int, _ item: ParagraphItem) -> some View {
        let on = selected.contains(idx)
        let alreadySaved = !on && isSaved(item)
        return Button {
            if on { selected.remove(idx) } else { selected.insert(idx) }
        } label: {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: on ? "checkmark.square.fill" : "square")
                    .font(.system(size: 15)).foregroundStyle(on ? Theme.accent : Theme.textTertiary)
                    .padding(.top, 1)
                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 8) {
                        Text(item.word ?? "").font(.system(size: 14, weight: .medium))
                            .foregroundStyle(alreadySaved ? Theme.textSecondary : Theme.textPrimary)
                        if let c = item.cefr { Pill.cefr(c) }
                        if let m = item.meaningVi {
                            Text("— \(m)").font(.system(size: 13)).foregroundStyle(Theme.textSecondary).lineLimit(1)
                        }
                    }
                    if alreadySaved {
                        Text(L.t("Already in library · unchecked to avoid a duplicate",
                                 "Đã có trong thư viện · bỏ chọn để tránh trùng"))
                            .font(.system(size: 12)).foregroundStyle(Theme.textTertiary)
                    } else if let r = item.reasonToLearn {
                        Text(r).font(.system(size: 12)).foregroundStyle(Theme.textTertiary).lineLimit(2)
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
            Text(L.t("Selected \(selected.count) / \(items.count)",
                     "Đã chọn \(selected.count) / \(items.count)"))
                .font(.system(size: 12)).foregroundStyle(Theme.textTertiary)
            Spacer()
            Button(L.t("Select all", "Chọn tất cả")) { selected = Set(items.indices) }
                .buttonStyle(.vSecondary)
            Button(L.t("Save \(selected.count) to library", "Lưu \(selected.count) vào thư viện")) { addSelected() }
                .buttonStyle(.vPrimary).disabled(selected.isEmpty)
        }
        .padding(14).background(Theme.bgSecondary)
    }

    // MARK: Logic

    /// Words among candidates already in the library (dedupe).
    private func existingSaved() -> Set<String> {
        var saved = Set<String>()
        for item in items {
            guard let word = item.word else { continue }
            if let _ = (try? env.entries.find(rawText: word, language: language)) ?? nil {
                saved.insert(TextKey.normalize(word))
            }
        }
        return saved
    }

    private func recomputeSelection() {
        savedSet = existingSaved()
        selected = ParagraphSelection.defaultSelection(items: items, existingNormalized: savedSet)
    }

    private func isSaved(_ item: ParagraphItem) -> Bool {
        guard let w = item.word else { return false }
        return savedSet.contains(TextKey.normalize(w))
    }

    private func changeMinLevel(_ lvl: CEFR) {
        // The `!working` guard plus the Menu's `.disabled(working)` prevent overlapping
        // re-extracts, so a slow response can't overwrite a newer list. Keep both in sync.
        guard lvl != minLevel, !working else { return }
        minLevel = lvl
        errorText = nil
        working = true
        Task {
            do {
                let newItems = try await env.capture.reextractParagraph(
                    text: rawText, language: language, minLevel: lvl)
                await MainActor.run {
                    items = newItems
                    recomputeSelection()
                    working = false
                }
            } catch {
                await MainActor.run {
                    errorText = L.t("Couldn't re-extract — keeping current list.",
                                    "Không trích xuất lại được — giữ danh sách hiện tại.")
                    working = false
                }
            }
        }
    }

    private func addSelected() {
        var ids: [Int64] = []
        for idx in selected.sorted() {
            if let id = try? env.capture.persistParagraphItem(items[idx], language: language,
                                                              source: source, sourceText: rawText) {
                ids.append(id)
            }
        }
        WindowManager.notifyDataChanged()
        onClose()
        // Background prep so each detail is ready when opened (bounded concurrency).
        Task { await env.prefetcher.prefetch(ids: ids) }
    }
}
