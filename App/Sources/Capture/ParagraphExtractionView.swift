import SwiftUI
import VokabKit

/// Paragraph extraction (SPEC §12 surface #3, mockup #3): the captured paragraph
/// shown with candidate words highlighted, a Min-level filter that re-runs agy,
/// and a dedupe-aware checklist with "Add N to deck". Persists chosen items.
///
/// Architecture:
///  - `allItems`      — master accumulating list (grows when user lowers minLevel via agy)
///  - `lowestFetched` — lowest CEFR level already fetched; raising minLevel is client-side
///    filter only (no agy call); lowering below lowestFetched triggers reextract+merge
///  - `selected`      — Set<String> of normalized word keys (stable across merges)
///  - `savedSet`      — normalized words already in library (shown as non-interactive section)
struct ParagraphExtractionView: View {
    @EnvironmentObject var env: AppEnvironment
    let source: SourceContext
    let language: String
    let rawText: String
    let onClose: () -> Void

    @State private var allItems: [ParagraphItem]            // master accumulating list
    @State private var translationViState: String?          // may be updated on lower
    @State private var lowestFetched: CEFR                  // lowest level already fetched
    @State private var minLevel: CEFR = .b1
    @State private var selected: Set<String> = []           // normalized word keys
    @State private var savedSet: Set<String> = []           // normalized words already in library
    @State private var working = false
    @State private var errorText: String?
    @State private var warningText: String?
    @State private var translationExpanded = true

    init(items: [ParagraphItem], translationVi: String? = nil, failedChunks: Int = 0,
         source: SourceContext, language: String,
         rawText: String, onClose: @escaping () -> Void) {
        _allItems = State(initialValue: items)
        _translationViState = State(initialValue: translationVi)
        // The initial items were extracted at minLevel (default .b1); anything lower
        // hasn't been fetched yet. Use .b1 as the default lowestFetched to match
        // the settings default — onAppear will sync both from env.settings.
        _lowestFetched = State(initialValue: .b1)
        _warningText = State(initialValue: failedChunks > 0
            ? L.t("\(failedChunks) section(s) couldn't be analyzed — showing the rest.",
                  "\(failedChunks) đoạn không trích xuất được — đang hiển thị phần còn lại.")
            : nil)
        self.source = source
        self.language = language
        self.rawText = rawText
        self.onClose = onClose
    }

    // MARK: - Derived views

    /// Items at or above the current minLevel (client filter over master list).
    private var selectableItems: [ParagraphItem] {
        ParagraphFilter.atOrAbove(allItems, minLevel: minLevel)
            .filter { item in
                let key = TextKey.normalize(item.word ?? "")
                return !key.isEmpty && !savedSet.contains(key)
            }
    }

    /// Items among allItems that are already in the library.
    private var savedItems: [ParagraphItem] {
        ParagraphFilter.atOrAbove(allItems, minLevel: minLevel)
            .filter { item in
                let key = TextKey.normalize(item.word ?? "")
                return !key.isEmpty && savedSet.contains(key)
            }
    }

    var body: some View {
        VStack(spacing: 0) {
            sourceBlock
            Hairline()
            filterBar
            if let errorText { errorBanner(errorText) }
            if let warningText { warningBanner(warningText) }
            Hairline()
            listContent
            Hairline()
            footer
        }
        .frame(minWidth: 520, minHeight: 420)
        .background(Theme.bgPrimary)
        .overlay { if working { loadingOverlay } }
        .onAppear {
            let lvl = env.settings.minParagraphLevel
            minLevel = lvl
            lowestFetched = lvl
            recomputeSavedSet()
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

            if let tv = translationViState, !tv.isEmpty {
                translationBlock(tv)
            }
        }
        .padding(16).frame(maxWidth: .infinity, alignment: .leading)
    }

    private var highlightedText: Text {
        var attr = AttributedString()
        let candidates = allItems.compactMap { $0.word }
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

    @ViewBuilder
    private func translationBlock(_ text: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Button {
                withAnimation(.easeInOut(duration: 0.18)) { translationExpanded.toggle() }
            } label: {
                HStack(spacing: 4) {
                    SecLabel(L.t("Vietnamese translation", "Bản dịch tiếng Việt"))
                    Spacer()
                    Image(systemName: translationExpanded ? "chevron.up" : "chevron.down")
                        .font(.system(size: 10)).foregroundStyle(Theme.textTertiary)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if translationExpanded {
                Text(text)
                    .font(.system(size: 13)).foregroundStyle(Theme.textSecondary)
                    .lineSpacing(3)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .padding(.top, 8)
    }

    // MARK: Filter bar + Min level

    private var filterBar: some View {
        HStack(spacing: 8) {
            Image(systemName: "line.3.horizontal.decrease.circle")
                .font(.system(size: 13)).foregroundStyle(Theme.textTertiary)
            Text(L.t("\(selectableItems.count) worth learning · basic words (A1–A2) filtered out",
                     "\(selectableItems.count) từ đáng học · đã lọc bỏ từ cơ bản (A1–A2)"))
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

    private func warningBanner(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 12)).foregroundStyle(Theme.highlightText)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 16).padding(.vertical, 8)
            .background(Theme.highlightBg)
    }

    private var loadingOverlay: some View {
        ZStack {
            Color.black.opacity(0.04)
            ProgressView().controlSize(.large)
        }
    }

    // MARK: List

    @ViewBuilder private var listContent: some View {
        let selectable = selectableItems
        let saved = savedItems
        if selectable.isEmpty && saved.isEmpty {
            ContentUnavailableView(L.t("No vocabulary found", "Không có từ nào"),
                                   systemImage: "text.magnifyingglass")
                .frame(maxHeight: .infinity)
        } else {
            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(selectable, id: \.word) { item in
                        selectableRow(item)
                        Hairline()
                    }
                    if !saved.isEmpty {
                        savedSectionHeader(count: saved.count)
                        ForEach(saved, id: \.word) { item in
                            savedRow(item)
                            Hairline()
                        }
                    }
                }
            }
        }
    }

    private func selectableRow(_ item: ParagraphItem) -> some View {
        let key = TextKey.normalize(item.word ?? "")
        let on = selected.contains(key)
        return Button {
            if on { selected.remove(key) } else { selected.insert(key) }
        } label: {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: on ? "checkmark.square.fill" : "square")
                    .font(.system(size: 15)).foregroundStyle(on ? Theme.accent : Theme.textTertiary)
                    .padding(.top, 1)
                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 8) {
                        Text(item.word ?? "").font(.system(size: 14, weight: .medium))
                            .foregroundStyle(Theme.textPrimary)
                        if let c = item.cefr { Pill.cefr(c) }
                        if let m = item.meaningVi {
                            Text("— \(m)").font(.system(size: 13)).foregroundStyle(Theme.textSecondary).lineLimit(1)
                        }
                    }
                    if let r = item.reasonToLearn {
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

    private func savedSectionHeader(count: Int) -> some View {
        HStack {
            Text(L.t("Already in library (\(count))", "Đã có trong thư viện (\(count))"))
                .font(.system(size: 11, weight: .medium)).foregroundStyle(Theme.textTertiary)
            Spacer()
        }
        .padding(.horizontal, 16).padding(.vertical, 6)
        .background(Theme.bgSecondary)
    }

    private func savedRow(_ item: ParagraphItem) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "checkmark.square.fill")
                .font(.system(size: 15)).foregroundStyle(Theme.textTertiary.opacity(0.5))
                .padding(.top, 1)
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 8) {
                    Text(item.word ?? "").font(.system(size: 14, weight: .medium))
                        .foregroundStyle(Theme.textSecondary)
                    if let c = item.cefr { Pill.cefr(c) }
                    if let m = item.meaningVi {
                        Text("— \(m)").font(.system(size: 13)).foregroundStyle(Theme.textTertiary).lineLimit(1)
                    }
                }
                Text(L.t("Already in library · skip to avoid duplicate",
                         "Đã có trong thư viện · bỏ qua để tránh trùng"))
                    .font(.system(size: 12)).foregroundStyle(Theme.textTertiary)
            }
            Spacer()
        }
        .padding(.horizontal, 16).padding(.vertical, 11)
        .opacity(0.7)
    }

    // MARK: Footer

    private var footer: some View {
        HStack {
            Text(L.t("Selected \(selected.count) / \(selectableItems.count)",
                     "Đã chọn \(selected.count) / \(selectableItems.count)"))
                .font(.system(size: 12)).foregroundStyle(Theme.textTertiary)
            Spacer()
            Button(L.t("Select all", "Chọn tất cả")) {
                selected = Set(selectableItems.compactMap {
                    let k = TextKey.normalize($0.word ?? ""); return k.isEmpty ? nil : k
                })
            }
            .buttonStyle(.vSecondary)
            Button(L.t("Save \(selected.count) to library", "Lưu \(selected.count) vào thư viện")) { addSelected() }
                .buttonStyle(.vPrimary).disabled(selected.isEmpty)
        }
        .padding(14).background(Theme.bgSecondary)
    }

    // MARK: Logic

    /// Words among allItems already in the library (normalized keys).
    private func buildSavedSet() -> Set<String> {
        var saved = Set<String>()
        for item in allItems {
            guard let word = item.word else { continue }
            if let _ = (try? env.entries.find(rawText: word, language: language)) ?? nil {
                saved.insert(TextKey.normalize(word))
            }
        }
        return saved
    }

    private func recomputeSavedSet() {
        savedSet = buildSavedSet()
        // Seed selection: all new words not yet in library
        selected = ParagraphSelection.defaultSelection(items: allItems, existingNormalized: savedSet)
    }

    private func changeMinLevel(_ lvl: CEFR) {
        guard lvl != minLevel, !working else { return }

        let raising = CEFR.allCases.firstIndex(of: lvl)! >= CEFR.allCases.firstIndex(of: lowestFetched)!

        if raising {
            // Raise: purely client-side filter, no agy call needed
            minLevel = lvl
            errorText = nil
        } else {
            // Lower below previously fetched: need agy call to get the extra words
            minLevel = lvl
            errorText = nil
            warningText = nil
            working = true
            Task {
                do {
                    let result = try await env.capture.reextractParagraph(
                        text: rawText, language: language, minLevel: lvl)
                    await MainActor.run {
                        // Merge: preserve existing allItems, add new ones from lower level
                        allItems = ParagraphMerge.union(allItems, result.items)
                        // Update translation if we got a better one
                        if translationViState == nil, let tv = result.translationVi {
                            translationViState = tv
                        }
                        lowestFetched = lvl
                        // Recompute savedSet and extend selected with any newly merged words
                        let newSaved = buildSavedSet()
                        savedSet = newSaved
                        let newKeys = Set(result.items.compactMap { item -> String? in
                            let k = TextKey.normalize(item.word ?? "")
                            guard !k.isEmpty, !newSaved.contains(k) else { return nil }
                            return k
                        })
                        selected.formUnion(newKeys)
                        // Drop any selection keys that didn't survive the merge
                        let presentKeys = Set(allItems.compactMap { item -> String? in
                            let k = TextKey.normalize(item.word ?? ""); return k.isEmpty ? nil : k
                        })
                        selected.formIntersection(presentKeys)
                        if result.failedChunks > 0 {
                            warningText = L.t("\(result.failedChunks) section(s) couldn't be analyzed — showing the rest.",
                                             "\(result.failedChunks) đoạn không trích xuất được — đang hiển thị phần còn lại.")
                        }
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
    }

    private func addSelected() {
        var ids: [Int64] = []
        for item in allItems {
            let key = TextKey.normalize(item.word ?? "")
            guard !key.isEmpty, selected.contains(key) else { continue }
            if let id = try? env.capture.persistParagraphItem(item, language: language,
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
