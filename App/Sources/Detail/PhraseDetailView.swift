import SwiftUI
import VokabKit

/// Phrase / idiom detail (SPEC §12 surface #1).
struct PhraseDetailView: View {
    @Environment(\.displayScale) private var displayScale
    @EnvironmentObject private var env: AppEnvironment
    @State private var current: Entry
    @State private var enriching = false
    @State private var tab: Tab = .variations
    @State private var showLegend = false
    @State private var addingExamples = false
    private let context: DetailContext

    init(entry: Entry, context: DetailContext = .library) {
        _current = State(initialValue: entry)
        self.context = context
    }

    enum Tab: String, CaseIterable, Identifiable {
        case variations = "Variations"
        case errors = "Common errors"
        case related = "Related"
        var id: String { rawValue }
    }

    private var entry: Entry { current }
    private var card: PhraseCard? { CardDecoding.phrase(current) }

    /// Phrases to underline as a unit inside example/seen-in sentences: the phrase
    /// itself plus any multi-word variations and related phrases.
    private var knownPhrases: [String] {
        let c = card
        return [entry.rawText]
            + (c?.variations ?? [])
            + (c?.relatedPhrases ?? []).filter { $0.trimmingCharacters(in: .whitespaces).contains(" ") }
    }

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    if entry.analysisState == AnalysisState.analyzing.rawValue {
                        analyzingPlaceholder
                    } else if entry.analysisState == AnalysisState.failed.rawValue {
                        failedView
                    } else {
                        phraseRow
                        metaStrip
                        formulaBox
                        Hairline()
                        seenIn
                        twoColumns
                        contextOfUseSection
                        grammarSection
                        tabs
                        tabContent
                    }
                }
            }
            if context.isCapture { captureBottomBar } else { bottomBar }
        }
        .background(Theme.bgPrimary)
        .task {
            if !current.enriched {
                enriching = true
                let updated = try? await env.enrichment.enrich(entry: current)
                withAnimation(.easeOut(duration: 0.25)) {
                    if let updated { current = updated }
                    enriching = false
                }
                if updated != nil { WindowManager.notifyDataChanged() }
            }
            if current.category == nil,
               let backfilled = try? await env.categoryBackfiller.backfill(entry: current) {
                current.category = backfilled
                WindowManager.notifyDataChanged()
            }
            if current.cardType == .phrase, let c = CardDecoding.phrase(current),
               c.commonErrors.isEmpty || c.contextOfUse == nil || c.grammarNote == nil
                   || ((c.meaning?.isEmpty != false) && (c.meaningEn?.isEmpty != false)),
               let updated = try? await env.phraseErrorBackfiller.backfill(entry: current) {
                current = updated
                WindowManager.notifyDataChanged()
            }
        }
    }

    // MARK: Analysis state placeholders

    private var analyzingPlaceholder: some View {
        AnalysisSkeletonView(
            rawText: entry.rawText,
            titleSize: 20,
            verticalPadding: 14,
            placeholderLines: [
                SkeletonLine("Placeholder phrase type and register", size: 13),
                SkeletonLine("Placeholder meaning text while analyzing", size: 14, weight: .medium),
                SkeletonLine("Placeholder usage note for skeleton shape", size: 13)
            ]
        )
    }

    private var failedView: some View {
        AnalysisFailedView(
            rawText: entry.rawText,
            titleSize: 20,
            verticalPadding: 14
        ) {
            guard let id = entry.id else { return }
            env.retryAnalysis(id: id)
        }
    }

    // MARK: Phrase row

    private var phraseRow: some View {
        // Responsive header: when the phrase identity + category fit on one line,
        // category sits top-right; otherwise it drops to its own line below. The
        // phrase identity never wraps mid-phrase to make room for the category.
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .firstTextBaseline, spacing: 12) {
                phraseIdentity.fixedSize(horizontal: true, vertical: false)   // demand one line
                Spacer(minLength: 12)
                categoryControl
            }
            VStack(alignment: .leading, spacing: 10) {
                phraseIdentity
                categoryControl
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 16).padding(.top, 14).padding(.bottom, 10)
    }

    /// Colored tokens + audio + meta — the phrase's identity line. No "Phrase"
    /// prefix: it doubled the "· phrasal verb" type meta and the single-word
    /// header carries no type prefix either (deliberate deviation from mockup,
    /// see SPEC §12).
    private var phraseIdentity: some View {
        FlowLayout(spacing: 6) {
            ForEach(Array(taggedTokens.enumerated()), id: \.offset) { _, token in
                if let colors = Theme.tokenColors(token.pos) {
                    Text(token.text)
                        .font(.system(size: 14, weight: .medium))
                        .padding(.horizontal, 10).padding(.vertical, 4)
                        .background(colors.bg, in: RoundedRectangle(cornerRadius: Theme.radiusMd))
                        .foregroundStyle(colors.fg)
                        .help(POSColorizer.posLabel(token.pos) ?? "")
                } else {
                    Text(token.text)
                        .font(.system(size: 14)).foregroundStyle(Theme.textTertiary)
                        .padding(.vertical, 4)
                }
            }
            PronounceButton(text: entry.rawText,
                            accent: Accent(settingsValue: env.settings.pronunciationAccent),
                            size: .small)
            if let type = card?.type {
                Text("· \(entry.language.uppercased()) · \(type)")
                    .font(.system(size: 13)).foregroundStyle(Theme.textTertiary)
                    .fixedSize()   // wrap as a whole unit, never break "· EN ·" / "idiom"
            }
            // Color legend ⓘ trails the meta — sits with the row's info, opens
            // the pill color key on demand.
            Button { showLegend.toggle() } label: {
                Image(systemName: "info.circle").font(.system(size: 11)).foregroundStyle(Theme.textTertiary)
            }
            .buttonStyle(.plain)
            .help(L.t("What the colors mean", "Màu các pill nghĩa là gì"))
            .popover(isPresented: $showLegend, arrowEdge: .bottom) { legendPopover }
        }
    }

    private var categoryControl: some View {
        CategoryPill(current: current.category) { picked in
            if let id = current.id {
                try? env.entries.setCategory(id: id, category: picked)
                current.category = picked
                WindowManager.notifyDataChanged()
            }
        }
        .fixedSize()
    }

    /// Words of the phrase tagged with part of speech (on-device).
    private var taggedTokens: [(text: String, pos: String?)] {
        POSColorizer.taggedWords(entry.rawText)
    }

    /// Self-demonstrating color key: each row is an actual pill in its color,
    /// so the user learns the whole system at a glance (SPEC §12 tokens).
    private var legendPopover: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(L.t("Pills are colored by word type", "Pill được tô màu theo từ loại"))
                .font(.system(size: 11, weight: .semibold)).foregroundStyle(Theme.textTertiary)
            ForEach(["verb", "noun", "prep", "adv"], id: \.self) { pos in
                if let colors = Theme.tokenColors(pos), let name = POSColorizer.posLabel(pos) {
                    Text(name)
                        .font(.system(size: 13, weight: .medium))
                        .padding(.horizontal, 10).padding(.vertical, 4)
                        .background(colors.bg, in: RoundedRectangle(cornerRadius: Theme.radiusMd))
                        .foregroundStyle(colors.fg)
                }
            }
            Text(L.t("Other words stay plain.", "Từ loại khác để trơn."))
                .font(.system(size: 11)).foregroundStyle(Theme.textTertiary)
        }
        .padding(14)
    }

    // MARK: Meta strip (reference facts about the phrase)

    /// A compact reference line under the phrase identity: register, CEFR and
    /// separability. Type is intentionally omitted — it already shows in the
    /// header meta ("· English · Phrasal verb").
    @ViewBuilder private var metaStrip: some View {
        let hasRegister = (card?.register?.isEmpty == false)
        let hasCefr = (card?.cefrLevel?.cefrLevel != nil)
        let hasSeparable = (card?.separable != nil)
        if hasRegister || hasCefr || hasSeparable {
            FlowLayout(spacing: 14, lineSpacing: 6) {
                if let reg = card?.register, !reg.isEmpty {
                    metaFact(L.t("Register", "Văn phong")) { MultiPill(reg, style: .register) }
                }
                if let cefr = card?.cefrLevel, cefr.cefrLevel != nil {
                    metaFact("CEFR") { Pill.cefr(cefr) }
                }
                if let sep = card?.separable {
                    metaFact(L.t("Separable", "Tách được")) {
                        Text(sep ? L.t("Yes", "Có") : L.t("No", "Không"))
                            .font(.system(size: 12, weight: .medium)).foregroundStyle(Theme.textPrimary)
                    }
                }
            }
            .padding(.horizontal, 16).padding(.bottom, 12)
        }
    }

    private func metaFact<V: View>(_ key: String, @ViewBuilder _ value: () -> V) -> some View {
        HStack(spacing: 6) {
            Text(key).font(.system(size: 11)).foregroundStyle(Theme.textTertiary)
            value()
        }
    }

    // MARK: Formula box

    @ViewBuilder private var formulaBox: some View {
        if let formula = card?.formulaPattern, !formula.isEmpty {
            VStack(alignment: .leading, spacing: 6) {
                SecLabel("Formula pattern")
                formulaColored(formula)
                if let confidence = card?.patternConfidence {
                    let v = max(0, min(1, confidence))
                    GeometryReader { geo in
                        ZStack(alignment: .leading) {
                            Capsule().fill(Theme.borderTertiary).frame(height: 4)
                            Capsule().fill(Theme.accent).frame(width: geo.size.width * v, height: 4)
                        }
                    }
                    .frame(height: 4).padding(.top, 4)
                    HStack {
                        Text("Pattern confidence").font(.system(size: 11)).foregroundStyle(Theme.textTertiary)
                        Spacer()
                        Text("\(Int(v * 100))%").font(.system(size: 11, weight: .medium)).foregroundStyle(Theme.accent)
                    }
                }
            }
            .padding(.horizontal, 14).padding(.vertical, 10)
            .background(Theme.bgSecondary, in: RoundedRectangle(cornerRadius: Theme.radiusMd))
            .padding(.horizontal, 16).padding(.bottom, 14)
        }
    }

    /// Renders the formula string with role tokens colored (V/adv/prep/noun)
    /// and operators dimmed, matching the mockup.
    private func formulaColored(_ formula: String) -> some View {
        let tokens = formula.split(separator: " ").map(String.init)
        return FlowLayout(spacing: 5) {
            ForEach(Array(tokens.enumerated()), id: \.offset) { _, token in
                if let colors = Theme.tokenColors(POSColorizer.formulaRole(token)) {
                    Text(token).font(Theme.mono(13, weight: .medium)).foregroundStyle(colors.fg)
                } else if ["+", "→", "->", "/", "|"].contains(token) {
                    Text(token).font(Theme.mono(13)).foregroundStyle(Theme.textTertiary)
                } else {
                    Text(token).font(Theme.mono(13)).foregroundStyle(Theme.textPrimary)
                }
            }
        }
    }

    // MARK: Two columns

    private var twoColumns: some View {
        HStack(alignment: .top, spacing: 0) {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 6) {
                    SecLabel("Examples")
                    if addingExamples {
                        ActivityDots(diameter: 4)
                    } else {
                        Button { addExamples() } label: {
                            Image(systemName: "plus.circle").font(.system(size: 12))
                        }
                        .buttonStyle(.plain).foregroundStyle(Theme.textSecondary)
                        .help(L.t("Add an example", "Thêm ví dụ"))
                        .accessibilityLabel(L.t("Add an example", "Thêm ví dụ"))
                    }
                    Spacer(minLength: 0)
                }
                examplesList
            }
            .frame(maxWidth: .infinity, alignment: .leading).padding(14)

            Rectangle().fill(Theme.borderTertiary).frame(width: Theme.hairline(displayScale))

            VStack(alignment: .leading, spacing: 6) {
                SecLabel("Meaning")
                if let m = card?.meaning(forLanguage: env.settings.meaningLanguage) {
                    Text(m).font(.system(size: 14, weight: .medium)).foregroundStyle(Theme.textPrimary)
                }
                if let en = card?.meaningEn, en != card?.meaning(forLanguage: env.settings.meaningLanguage) {
                    InteractiveText(sentence: en, knownPhrases: knownPhrases, language: entry.language,
                                    fontSize: 13, color: Theme.textSecondary)
                        .lineSpacing(3)
                }
                if let note = card?.usageNote {
                    // English usage explanation — tappable for lookup/capture.
                    InteractiveText(sentence: note, knownPhrases: knownPhrases, language: entry.language,
                                    fontSize: 13, color: Theme.textSecondary)
                        .lineSpacing(2).padding(.top, 2)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading).padding(14)
        }
    }

    /// The example rows: content-sized for a few, but capped + internally
    /// scrollable once the list grows long (so it doesn't unbalance the columns).
    @ViewBuilder private var examplesList: some View {
        let examples = card?.examples ?? []
        if examples.isEmpty {
            Text(L.t("No examples yet.", "Chưa có ví dụ."))
                .font(.system(size: 13)).foregroundStyle(Theme.textTertiary)
        } else {
            let rows = VStack(alignment: .leading, spacing: 8) {
                ForEach(Array(examples.enumerated()), id: \.offset) { _, example in
                    exampleRow(example)
                }
            }
            if examples.count > 3 {
                ScrollView { rows }.frame(maxHeight: 200)
            } else {
                rows
            }
        }
    }

    private func exampleRow(_ example: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            InteractiveText(sentence: EnglishDisplay.sentence(example),
                            knownPhrases: knownPhrases, language: entry.language)
                .lineSpacing(3)
                .padding(.leading, 10)
                .overlay(alignment: .leading) { Rectangle().fill(Theme.borderSecondary).frame(width: 2) }
                .frame(maxWidth: .infinity, alignment: .leading)
            PronounceButton(text: example,
                            accent: Accent(settingsValue: env.settings.pronunciationAccent),
                            size: .small)
        }
    }

    /// Fetches more examples from agy and appends the unique ones to the stored card.
    private func addExamples() {
        guard let id = entry.id, !addingExamples, var c = card else { return }
        addingExamples = true
        Task {
            defer { addingExamples = false }
            let more: [String]
            do {
                more = try await env.agy.morePhraseExamples(entry.rawText, existing: c.examples)
            } catch {
                await MainActor.run { notify(L.t("Couldn't load examples", "Không tải được ví dụ"), danger: true) }
                return
            }
            let merged = ExampleMatching.merge(c.examples, adding: more)
            guard merged.count > c.examples.count else {     // all duplicates / nothing new
                await MainActor.run { notify(L.t("No new examples", "Không có ví dụ mới")) }
                return
            }
            c.examples = merged
            do {
                let data = try JSONEncoder().encode(c)
                try env.entries.setAiResult(id: id, aiResult: String(decoding: data, as: UTF8.self))
            } catch {
                await MainActor.run { notify(L.t("Couldn't add examples", "Không thêm được ví dụ"), danger: true) }
                return
            }
            if let refreshed = try? env.entries.entry(id: id) {
                await MainActor.run { current = refreshed }   // new examples appear inline — no toast needed
            }
            WindowManager.notifyDataChanged()
        }
    }

    /// Shows a self-dismissing corner toast at the user's configured position.
    @MainActor private func notify(_ text: String, danger: Bool = false) {
        ToastCenter.shared.corner = env.settings.toastPosition
        ToastCenter.shared.notice(text, danger: danger)
    }

    // MARK: Seen in

    @ViewBuilder private var seenIn: some View {
        if let sentence = entry.captureSentence {
            VStack(alignment: .leading, spacing: 8) {
                SecLabel("Seen in")
                InteractiveText(sentence: sentence, knownPhrases: knownPhrases,
                                language: entry.language, highlight: entry.rawText)
                    .lineSpacing(3)
                    .padding(.leading, 10)
                    .overlay(alignment: .leading) { Rectangle().fill(Theme.accent).frame(width: 2) }
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 16).padding(.vertical, 14)
        }
    }

    // MARK: Context of use

    @ViewBuilder private var contextOfUseSection: some View {
        if let text = card?.contextOfUse, !text.isEmpty {
            VStack(alignment: .leading, spacing: 6) {
                SecLabel(L.t("Context of use", "Bối cảnh dùng"))
                Text(text)
                    .font(.system(size: 13)).foregroundStyle(Theme.textSecondary).lineSpacing(3)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 16).padding(.vertical, 14)
        } else if enriching {
            VStack(alignment: .leading, spacing: 6) {
                SecLabel(L.t("Context of use", "Bối cảnh dùng"))
                Text("Placeholder context-of-use sentence that spans a couple of lines here")
                    .font(.system(size: 13)).foregroundStyle(Theme.textSecondary).lineSpacing(3)
                    .skeleton()
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 16).padding(.vertical, 14)
            .transition(.opacity)
        }
    }

    // MARK: Grammar & tense

    @ViewBuilder private var grammarSection: some View {
        if let text = card?.grammarNote, !text.isEmpty {
            VStack(alignment: .leading, spacing: 6) {
                SecLabel(L.t("Grammar & tense", "Ngữ pháp & thì"))
                Text(text)
                    .font(.system(size: 13)).foregroundStyle(Theme.textSecondary).lineSpacing(3)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 16).padding(.vertical, 14)
        } else if enriching {
            VStack(alignment: .leading, spacing: 6) {
                SecLabel(L.t("Grammar & tense", "Ngữ pháp & thì"))
                Text("Placeholder grammar and tense note line for skeleton shape")
                    .font(.system(size: 13)).foregroundStyle(Theme.textSecondary).lineSpacing(3)
                    .skeleton()
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 16).padding(.vertical, 14)
            .transition(.opacity)
        }
    }

    // MARK: Tabs

    private var tabs: some View {
        HStack(spacing: 2) {
            ForEach(Tab.allCases) { t in
                Button { tab = t } label: {
                    Text(t.rawValue)
                        .font(.system(size: 12))
                        .foregroundStyle(tab == t ? Theme.textPrimary : Theme.textSecondary)
                        .padding(.horizontal, 12).padding(.vertical, 7)
                        .overlay(alignment: .bottom) {
                            Rectangle().fill(tab == t ? Theme.textPrimary : .clear).frame(height: 2)
                        }
                }
                .buttonStyle(.plain)
            }
            Spacer()
        }
        .padding(.horizontal, 16)
        .overlay(alignment: .bottom) { Hairline() }
    }

    @ViewBuilder private var tabContent: some View {
        switch tab {
        case .variations: varGrid(card?.variations ?? [], danger: false)
        case .errors:     errorList
        case .related:    relatedChips
        }
    }

    @ViewBuilder private var errorList: some View {
        let items = card?.commonErrors ?? []
        if items.isEmpty {
            Text(L.t("Nothing here.", "Chưa có.")).font(.system(size: 13)).foregroundStyle(Theme.textTertiary).padding(16)
        } else {
            VStack(alignment: .leading, spacing: 10) {
                ForEach(Array(items.enumerated()), id: \.offset) { _, item in
                    errorCard(item)
                }
            }
            .padding(.horizontal, 16).padding(.vertical, 12)
        }
    }

    /// One common-error item: the sentence with the correct answer marked ✓
    /// green and the wrong options marked ✗ red, so the mistake is visible
    /// (not silently corrected). Falls back to plain text if there's no blank.
    private func errorCard(_ item: ErrorQuiz) -> some View {
        let parts = item.sentence.components(separatedBy: ClozeBuilder.blank)
        let head = parts.first ?? item.sentence
        let tail = parts.count > 1 ? parts.dropFirst().joined(separator: ClozeBuilder.blank) : ""
        let hasBlank = parts.count > 1
        let answer = head.trimmingCharacters(in: .whitespaces).isEmpty
            ? EnglishDisplay.capitalizingFirst(item.answer) : item.answer
        let wrong = item.options.filter { $0.caseInsensitiveCompare(item.answer) != .orderedSame }
        return VStack(alignment: .leading, spacing: 5) {
            if hasBlank {
                (Text(EnglishDisplay.sentence(head))
                 + Text("✓\(answer)").foregroundColor(Theme.diffIns).bold()
                 + Text(EnglishDisplay.fixI(tail)))
                    .font(.system(size: 13)).foregroundStyle(Theme.textPrimary)
                if !wrong.isEmpty {
                    HStack(spacing: 12) {
                        ForEach(wrong, id: \.self) { opt in
                            Text("✗ \(opt)").font(.system(size: 12, weight: .medium))
                                .foregroundStyle(Theme.textDanger)
                        }
                    }
                }
            } else {
                Text(EnglishDisplay.sentence(item.sentence))
                    .font(.system(size: 13)).foregroundStyle(Theme.textPrimary)
            }
            if let note = item.noteVi, !note.isEmpty {
                Text(note).font(.system(size: 12)).foregroundStyle(Theme.textTertiary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 12).padding(.vertical, 10)
        .background(Theme.bgSecondary, in: RoundedRectangle(cornerRadius: Theme.radiusMd))
    }

    private func varGrid(_ items: [String], danger: Bool) -> some View {
        Group {
            if items.isEmpty && enriching {
                let columns = [GridItem(.flexible(), spacing: 8), GridItem(.flexible(), spacing: 8)]
                LazyVGrid(columns: columns, spacing: 8) {
                    ForEach(["placeholder item", "another item", "third item", "fourth item"], id: \.self) { item in
                        Text(item)
                            .font(.system(size: 13))
                            .foregroundStyle(danger ? Theme.textDanger : Theme.textSecondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal, 12).padding(.vertical, 10)
                            .background(danger ? Theme.bgDanger : Theme.bgSecondary,
                                        in: RoundedRectangle(cornerRadius: Theme.radiusMd))
                    }
                }
                .padding(.horizontal, 16).padding(.vertical, 12)
                .skeleton()
                .transition(.opacity)
            } else if items.isEmpty {
                Text(L.t("Nothing here.", "Chưa có.")).font(.system(size: 13)).foregroundStyle(Theme.textTertiary)
                    .padding(16)
            } else {
                let columns = [GridItem(.flexible(), spacing: 8), GridItem(.flexible(), spacing: 8)]
                LazyVGrid(columns: columns, spacing: 8) {
                    ForEach(items, id: \.self) { item in
                        InteractiveToken(text: item, hint: .phrase, language: entry.language,
                                         underlineOnHover: false) {
                            Text(item)
                                .font(.system(size: 13))
                                .foregroundStyle(danger ? Theme.textDanger : Theme.textSecondary)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(.horizontal, 12).padding(.vertical, 10)
                                .background(danger ? Theme.bgDanger : Theme.bgSecondary,
                                            in: RoundedRectangle(cornerRadius: Theme.radiusMd))
                        }
                    }
                }
                .padding(.horizontal, 16).padding(.vertical, 12)
            }
        }
    }

    private var relatedChips: some View {
        let items = card?.relatedPhrases ?? []
        return Group {
            if items.isEmpty && enriching {
                FlowLayout(spacing: 6) {
                    ForEach(["related", "another", "third", "fourth"], id: \.self) { Chip($0) }
                }
                .padding(.horizontal, 16).padding(.vertical, 14)
                .skeleton()
                .transition(.opacity)
            } else if items.isEmpty {
                Text(L.t("Nothing here.", "Chưa có.")).font(.system(size: 13)).foregroundStyle(Theme.textTertiary).padding(16)
            } else {
                FlowLayout(spacing: 6) {
                    ForEach(items, id: \.self) { InteractiveChip(text: $0, language: entry.language) }
                }
                .padding(.horizontal, 16).padding(.vertical, 14)
            }
        }
    }

    private var bottomBar: some View {
        VStack(spacing: 0) {
            Hairline()
            HStack {
                if let app = entry.sourceApp {
                    Text("Source: \(app)").font(.system(size: 12)).foregroundStyle(Theme.textTertiary)
                }
                Spacer()
                Button { PracticePresenter.shared.present(entry: entry) } label: {
                    Label(L.t("Practice writing", "Luyện viết"), systemImage: "pencil.line")
                }.buttonStyle(.vPrimary)
            }
            .padding(.horizontal, 14).padding(.vertical, 10).background(Theme.bgSecondary)
        }
    }

    private var captureBottomBar: some View {
        VStack(spacing: 0) {
            Hairline()
            HStack(spacing: 10) {
                Label(L.t("Saved", "Đã lưu"), systemImage: "checkmark.circle.fill")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(Theme.diffIns)
                if let app = entry.sourceApp {
                    Text("Source: \(app)\(entry.sourceURL.map { " · \($0)" } ?? "")")
                        .font(.system(size: 12)).foregroundStyle(Theme.textTertiary).lineLimit(1)
                }
                Spacer()
                Button(L.t("Done", "Xong")) { context.onDone?() }
                    .buttonStyle(.vPrimary)
            }
            .padding(.horizontal, 14).padding(.vertical, 10)
            .background(Theme.bgSecondary)
        }
    }
}
