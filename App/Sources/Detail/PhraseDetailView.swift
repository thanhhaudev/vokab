import SwiftUI
import VokabKit

/// Phrase / idiom detail (SPEC §12 surface #1).
struct PhraseDetailView: View {
    @EnvironmentObject private var env: AppEnvironment
    @State private var current: Entry
    @State private var enriching = false
    @State private var tab: Tab = .variations
    @State private var showLegend = false
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
               c.commonErrors.isEmpty || c.contextOfUse == nil || c.grammarNote == nil,
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
            VStack(alignment: .leading, spacing: 7) {
                SecLabel("Analysis")
                if let type = card?.type, !type.isEmpty { defRowMulti("Type", raw: type, style: .type) }
                if let register = card?.register, !register.isEmpty { defRowMulti("Register", raw: register, style: .register) }
                if let cefr = card?.cefrLevel, cefr.cefrLevel != nil { defRow("CEFR", pill: Pill.cefr(cefr)) }
                if let sep = card?.separable {
                    defRow("Separable?", value: sep ? "Yes" : "No")
                }
                if let example = card?.examples.first {
                    HStack(alignment: .top, spacing: 8) {
                        Text(EnglishDisplay.sentence(example)).font(.system(size: 13)).foregroundStyle(Theme.textPrimary)
                            .padding(.leading, 10).padding(.top, 4)
                            .overlay(alignment: .leading) { Rectangle().fill(Theme.borderSecondary).frame(width: 2) }
                            .frame(maxWidth: .infinity, alignment: .leading)
                        PronounceButton(text: example,
                                        accent: Accent(settingsValue: env.settings.pronunciationAccent),
                                        size: .small)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading).padding(14)

            Rectangle().fill(Theme.borderTertiary).frame(width: Theme.hairline)

            VStack(alignment: .leading, spacing: 6) {
                SecLabel("Meaning")
                if let vi = card?.meaningVi {
                    Text(vi).font(.system(size: 14, weight: .medium)).foregroundStyle(Theme.textPrimary)
                }
                if let en = card?.meaningEn {
                    Text(en).font(.system(size: 13)).foregroundStyle(Theme.textSecondary).lineSpacing(3)
                }
                if let note = card?.usageNote {
                    Text(note).font(.system(size: 13)).foregroundStyle(Theme.textSecondary).lineSpacing(2).padding(.top, 2)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading).padding(14)
        }
    }

    // MARK: Seen in

    @ViewBuilder private var seenIn: some View {
        if let sentence = entry.captureSentence {
            VStack(alignment: .leading, spacing: 8) {
                SecLabel("Seen in")
                HighlightedSentence(sentence: sentence, target: entry.rawText)
                    .font(.system(size: 13)).lineSpacing(3)
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
        }
    }

    private func defRow(_ key: String, pill: Pill) -> some View {
        HStack { Text(key).font(.system(size: 13)).foregroundStyle(Theme.textSecondary); Spacer(); pill }
    }
    private func defRowMulti(_ key: String, raw: String, style: PillStyle) -> some View {
        HStack { Text(key).font(.system(size: 13)).foregroundStyle(Theme.textSecondary); Spacer(); MultiPill(raw, style: style) }
    }
    private func defRow(_ key: String, value: String) -> some View {
        HStack {
            Text(key).font(.system(size: 13)).foregroundStyle(Theme.textSecondary)
            Spacer()
            Text(value).font(.system(size: 13, weight: .medium)).foregroundStyle(Theme.textPrimary)
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
                FlowLayout(spacing: 6) { ForEach(items, id: \.self) { Chip($0) } }
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
                    .foregroundStyle(Color(hex: 0x0F6E56))
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
