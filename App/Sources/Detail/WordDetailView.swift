import SwiftUI
import AppKit
import VokabKit

/// Single-word detail (SPEC §12 surface #2). Core fields render instantly;
/// tier-2 fields (etymology, synonyms, antonyms, word family) are fetched lazily
/// on first open and merged.
struct WordDetailView: View {
    @Environment(\.displayScale) private var displayScale
    @EnvironmentObject private var env: AppEnvironment
    @State private var current: Entry
    @State private var enriching = false
    @State private var backfilling = false
    @State private var addingExamples = false
    /// Measured content width; drives the 1-vs-2-column reference layout.
    @State private var contentWidth: CGFloat = 0
    private let context: DetailContext

    init(entry: Entry, context: DetailContext = .library) {
        _current = State(initialValue: entry)
        self.context = context
    }

    private var entry: Entry { current }
    private var card: WordCard? { CardDecoding.word(current) }

    private var hasForms: Bool { !(card?.forms.isEmpty ?? true) || loadingRelations }

    /// Sections fed by tier-2 relations enrichment OR the relations backfiller
    /// (old cards) are "pending" in both windows — so they skeleton, never pop in.
    private var loadingRelations: Bool { enriching || backfilling }

    /// True when the Relations group has any content (or is still enriching, where
    /// its subsections show skeletons) — so the group header is never shown bare.
    private var hasRelations: Bool {
        if enriching { return true }
        let c = card
        return !(c?.synonyms.isEmpty ?? true) || !(c?.antonyms.isEmpty ?? true)
            || !(c?.wordFamily.isEmpty ?? true) || !(c?.confusables.isEmpty ?? true)
            || (c?.etymology?.isEmpty == false)
    }

    /// Normalized captured surface, for highlighting its chip in the Forms row.
    private var capturedKey: String? {
        guard let f = current.capturedForm, !f.isEmpty else { return nil }
        return TextKey.normalize(f)
    }

    /// Phrases to underline as a unit inside example sentences: the word's own
    /// collocations plus any multi-word word-family entries (phrasal verbs, etc.).
    private var knownPhrases: [String] {
        let c = card
        return (c?.collocations ?? []) + (c?.wordFamily ?? []).filter {
            $0.trimmingCharacters(in: .whitespaces).contains(" ")
        }
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
                        header
                        Hairline()
                        sensesSection
                        Hairline()
                        formsSection
                        if hasForms { Hairline() }
                        referenceArea
                    }
                }
                .onGeometryChange(for: CGFloat.self, of: { $0.size.width }, action: { contentWidth = $0 })
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
            // Lazily classify Phase-1 entries that have no category yet.
            if current.category == nil,
               let backfilled = try? await env.categoryBackfiller.backfill(entry: current) {
                current.category = backfilled
                WindowManager.notifyDataChanged()
            }
            // Backfill collocations/confusables/contextOfUse/grammarNote for word
            // entries enriched before those fields existed. New captures already have
            // them from relations. Require a decodable card so a corrupt entry is never overwritten.
            if current.cardType == .word, let c = CardDecoding.word(current),
               (c.collocations.isEmpty && c.confusables.isEmpty) || c.contextOfUse == nil || c.grammarNote == nil || c.irregular == nil {
                backfilling = true
                let updated = try? await env.relationsBackfiller.backfill(entry: current)
                withAnimation(.easeOut(duration: 0.25)) {
                    if let updated { current = updated }
                    backfilling = false
                }
                if updated != nil { WindowManager.notifyDataChanged() }
            }
        }
    }

    // MARK: Analysis state placeholders

    private var analyzingPlaceholder: some View {
        AnalysisSkeletonView(
            rawText: entry.rawText,
            titleSize: 26,
            verticalPadding: 16,
            placeholderLines: [
                SkeletonLine("Placeholder meaning text shown while analyzing", size: 15),
                SkeletonLine("Placeholder definition text for skeleton shape", size: 13),
                SkeletonLine("Word family placeholder term", size: 13)
            ]
        )
    }

    private var failedView: some View {
        AnalysisFailedView(
            rawText: entry.rawText,
            titleSize: 26,
            verticalPadding: 16
        ) {
            guard let id = entry.id else { return }
            env.retryAnalysis(id: id)
        }
    }

    // MARK: Header

    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .lastTextBaseline, spacing: 12) {
                Text(entry.rawText)
                    .font(.system(size: 26, weight: .medium)).foregroundStyle(Theme.textPrimary)
                    .lineLimit(2).minimumScaleFactor(0.5)
                if let ipa = card?.ipa {
                    Text(ipa).font(Theme.mono(14)).foregroundStyle(Theme.textSecondary).lineLimit(1)
                }
                PronounceButton(text: entry.rawText,
                               accent: Accent(settingsValue: env.settings.pronunciationAccent))
                Spacer(minLength: 8)
                Text([entry.language.uppercased(), card?.frequency?.pillTokens().first]
                        .compactMap { $0 }.joined(separator: " · "))
                    .font(.system(size: 12)).foregroundStyle(Theme.textTertiary).lineLimit(1)
            }
            FlowLayout(spacing: 6) {
                MultiPill(card?.combinedPOS, style: .type)
                if let cefr = card?.cefrLevel, cefr.cefrLevel != nil { Pill.cefr(cefr) }
                MultiPill(card?.register, style: .register)
                CategoryPill(current: current.category) { picked in
                    if let id = current.id {
                        try? env.entries.setCategory(id: id, category: picked)
                        current.category = picked
                        WindowManager.notifyDataChanged()
                    }
                }
            }
        }
        .padding(.horizontal, 16).padding(.top, 16).padding(.bottom, 12)
    }

    // MARK: Senses (full width)

    private var sensesSection: some View {
        let senses = card?.resolvedSenses ?? []
        return VStack(alignment: .leading, spacing: 0) {
            SecLabel(senses.count > 1 ? L.t("Senses", "Các nghĩa") : L.t("Meaning", "Nghĩa"))
                .padding(.bottom, 11)
            ForEach(Array(senses.enumerated()), id: \.offset) { index, sense in
                if index > 0 { Hairline().padding(.vertical, 11) }
                senseRow(sense)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 16).padding(.vertical, 14)
    }

    // MARK: Forms (inflections)

    @ViewBuilder private var formsSection: some View {
        if let forms = card?.forms, !forms.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                SecLabel(L.t("Forms", "Dạng chia"))
                FlowLayout(spacing: 6) {
                    ForEach(forms, id: \.self) { f in
                        formChip(f)
                    }
                }
                if card?.irregular == true {
                    Label(L.t("irregular", "bất quy tắc"), systemImage: "exclamationmark.triangle")
                        .font(.system(size: 11))
                        .foregroundStyle(Theme.dyn(light: 0xB26B00, dark: 0xE0A33A))
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 16).padding(.vertical, 14)
        } else if loadingRelations {
            VStack(alignment: .leading, spacing: 8) {
                SecLabel(L.t("Forms", "Dạng chia"))
                FlowLayout(spacing: 6) {
                    ForEach(["running", "walked", "forms"], id: \.self) { Chip($0) }
                }
                .skeleton()
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 16).padding(.vertical, 14)
            .transition(.opacity)
        }
    }

    /// One form chip: the inflected word + a dim grammatical-role suffix, tappable
    /// to look up/capture. The chip matching the captured surface is accent-highlighted.
    @ViewBuilder private func formChip(_ f: WordForm) -> some View {
        let captured = capturedKey != nil && TextKey.normalize(f.form) == capturedKey
        InteractiveToken(text: f.form, hint: .word, language: entry.language,
                         underlineOnHover: false) {
            HStack(spacing: 5) {
                Text(f.form).font(.system(size: 12, weight: captured ? .semibold : .regular))
                if !f.label.isEmpty {
                    Text("· \(f.label)").font(.system(size: 11))
                        .foregroundStyle(captured ? Theme.accent.opacity(0.85) : Theme.textTertiary)
                }
                if captured {
                    Image(systemName: "checkmark").font(.system(size: 9, weight: .bold))
                        .foregroundStyle(Theme.accent)
                }
            }
            .padding(.horizontal, 10).padding(.vertical, 4)
            .background(captured ? Theme.accent.opacity(0.15) : Theme.bgPrimary, in: Capsule())
            .overlay(Capsule().strokeBorder(captured ? Theme.accent : Theme.borderSecondary,
                                            lineWidth: Theme.hairline(displayScale)))
            .foregroundStyle(captured ? Theme.accent : Theme.textSecondary)
        }
    }

    /// One sense: pos pill on its own line, then the meaning, then a dimmer
    /// interactive English gloss.
    @ViewBuilder private func senseRow(_ sense: WordCard.Sense) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                if let pos = sense.pos { Pill(pos, style: .type) }
                if sense.matchesContext {
                    Text(L.t("in context", "trong ngữ cảnh"))
                        .font(.system(size: 11)).foregroundStyle(Theme.accent)
                }
            }
            if let g = card?.gloss(sense, forLanguage: env.settings.meaningLanguage) {
                Text(g).font(.system(size: 14, weight: .medium)).foregroundStyle(Theme.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            if let en = sense.meaningEn,
               en != card?.gloss(sense, forLanguage: env.settings.meaningLanguage) {
                // English gloss: smaller, dimmer, still interactive (hover/click to capture).
                InteractiveText(sentence: en, knownPhrases: knownPhrases, language: entry.language,
                                fontSize: 12, color: Theme.textSecondary)
                    .lineSpacing(2)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.leading, sense.matchesContext ? 8 : 0)
        .overlay(alignment: .leading) {
            if sense.matchesContext { Rectangle().fill(Theme.accent).frame(width: 2) }
        }
    }

    // MARK: Word family (related-words cluster)

    @ViewBuilder private var wordFamilySection: some View {
        if let family = card?.wordFamily, !family.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                SecLabel("Word family")
                FlowLayout(spacing: 6) {
                    ForEach(family, id: \.self) { InteractiveChip(text: $0, language: entry.language) }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 16).padding(.vertical, 14)
        } else if enriching {
            VStack(alignment: .leading, spacing: 8) {
                SecLabel("Word family")
                FlowLayout(spacing: 6) {
                    ForEach(["placeholder", "another", "third"], id: \.self) { Chip($0) }
                }
                .skeleton()
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 16).padding(.vertical, 14)
            .transition(.opacity)
        }
    }

    // MARK: Group header helper

    /// A light heading that groups several sub-sections (e.g. "Usage", "Relations").
    private func groupHeader(_ title: String) -> some View {
        Text(title)
            .font(.system(size: 13, weight: .semibold))
            .foregroundStyle(Theme.textPrimary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 16).padding(.top, 14).padding(.bottom, 2)
    }

    // MARK: Reference sections (two columns when wide, one when narrow)

    /// The non-senses sections. On a wide detail pane they flow into two columns
    /// (senses keep full width above); on a narrow pane they stack in one column.
    @ViewBuilder private var referenceArea: some View {
        if contentWidth >= 560 {
            HStack(alignment: .top, spacing: 0) {
                VStack(alignment: .leading, spacing: 0) {
                    groupHeader(L.t("Usage", "Cách dùng"))
                    collocationsSection
                    grammarSection
                    contextOfUseSection
                    examples
                    seenIn
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                Rectangle().fill(Theme.borderTertiary).frame(width: Theme.hairline(displayScale))
                VStack(alignment: .leading, spacing: 0) {
                    if hasRelations { groupHeader(L.t("Relations", "Liên quan")) }
                    synAnt
                    wordFamilySection
                    confusablesSection
                    etymology
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        } else {
            VStack(alignment: .leading, spacing: 0) {
                groupHeader(L.t("Usage", "Cách dùng"))
                collocationsSection
                grammarSection
                contextOfUseSection
                examples
                seenIn
                if hasRelations { groupHeader(L.t("Relations", "Liên quan")) }
                synAnt
                wordFamilySection
                confusablesSection
                etymology
            }
        }
    }

    // MARK: Etymology band

    @ViewBuilder private var etymology: some View {
        if let ety = card?.etymology, !ety.isEmpty {
            VStack(alignment: .leading, spacing: 6) {
                SecLabel("Etymology")
                etymologyText(ety).font(.system(size: 13)).foregroundStyle(Theme.textSecondary).lineSpacing(3)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 16).padding(.vertical, 12)
            .background(Theme.bgSecondary)
            Hairline()
        } else if enriching {
            VStack(alignment: .leading, spacing: 6) {
                SecLabel("Etymology")
                Text("Placeholder etymology text that spans a couple of lines to mimic the real description block shape.")
                    .font(.system(size: 13)).foregroundStyle(Theme.textSecondary).lineSpacing(3)
                    .skeleton()
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 16).padding(.vertical, 12).background(Theme.bgSecondary)
            .transition(.opacity)
            Hairline()
        }
    }

    /// Etymology with source-language names highlighted in mono teal (mockup look).
    private func etymologyText(_ text: String) -> Text {
        let words = text.split(separator: " ").map(String.init)
        var result = Text("")
        for (i, word) in words.enumerated() {
            let piece: Text
            if POSColorizer.isLanguage(word) {
                piece = Text(word).font(Theme.mono(13)).foregroundColor(Theme.saveFg)
            } else {
                piece = Text(word)
            }
            result = (i == 0) ? piece : result + Text(" ") + piece
        }
        return result
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

    // MARK: Examples

    @ViewBuilder private var examples: some View {
        if card != nil {
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
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 16).padding(.vertical, 14)
        }
    }

    /// Example rows: content-sized for a few, capped + internally scrollable once long.
    @ViewBuilder private var examplesList: some View {
        let ex = card?.examples ?? []
        if ex.isEmpty {
            Text(L.t("No examples yet.", "Chưa có ví dụ."))
                .font(.system(size: 13)).foregroundStyle(Theme.textTertiary)
        } else {
            let rows = VStack(alignment: .leading, spacing: 8) {
                ForEach(Array(ex.enumerated()), id: \.offset) { _, example in
                    exampleRow(example)
                }
            }
            if ex.count > 3 {
                ScrollView { rows }.frame(maxHeight: 200)
            } else {
                rows
            }
        }
    }

    private func exampleRow(_ example: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            InteractiveText(sentence: example, knownPhrases: knownPhrases, language: entry.language)
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
                more = try await env.agy.moreWordExamples(entry.rawText, language: entry.language,
                                                          existing: c.examples)
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
                try env.entries.setAiResult(id: id, aiResult: c.encodedJSON())
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

    // MARK: Synonyms / antonyms

    @ViewBuilder private var synAnt: some View {
        let syn = card?.synonyms ?? []
        let ant = card?.antonyms ?? []
        if !syn.isEmpty || !ant.isEmpty {
            HStack(alignment: .top, spacing: 14) {
                if !syn.isEmpty { chipColumn("Synonyms", syn) }
                if !ant.isEmpty { chipColumn("Antonyms", ant) }
            }
            .padding(.horizontal, 16).padding(.vertical, 14)
        } else if enriching {
            VStack(alignment: .leading, spacing: 8) {
                SecLabel("Synonyms")
                FlowLayout(spacing: 6) {
                    ForEach(["synonym", "another", "third", "fourth"], id: \.self) { Chip($0) }
                }
                .skeleton()
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 16).padding(.vertical, 14)
            .transition(.opacity)
        }
    }

    // MARK: Collocations

    @ViewBuilder private var collocationsSection: some View {
        let cols = card?.collocations ?? []
        if !cols.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                SecLabel(L.t("Collocations", "Kết hợp từ"))
                FlowLayout(spacing: 6) {
                    ForEach(cols, id: \.self) { InteractiveChip(text: $0, language: entry.language) }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 16).padding(.vertical, 14)
        } else if loadingRelations {
            VStack(alignment: .leading, spacing: 8) {
                SecLabel(L.t("Collocations", "Kết hợp từ"))
                FlowLayout(spacing: 6) {
                    ForEach(["make a decision", "go for"], id: \.self) { Chip($0) }
                }
                .skeleton()
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 16).padding(.vertical, 14)
            .transition(.opacity)
        }
    }

    // MARK: Easily confused

    @ViewBuilder private var confusablesSection: some View {
        let items = card?.confusables ?? []
        if !items.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                SecLabel(L.t("Easily confused", "Dễ nhầm"))
                ForEach(items, id: \.word) { item in
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text(item.word)
                            .font(.system(size: 14, weight: .medium)).foregroundStyle(Theme.textPrimary)
                        if let note = item.noteVi, !note.isEmpty {
                            Text(note)
                                .font(.system(size: 13)).foregroundStyle(Theme.textSecondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 16).padding(.vertical, 14)
        } else if loadingRelations {
            VStack(alignment: .leading, spacing: 8) {
                SecLabel(L.t("Easily confused", "Dễ nhầm"))
                Text("Placeholder confusable word and its short note line")
                    .font(.system(size: 14)).foregroundStyle(Theme.textSecondary)
                    .skeleton()
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 16).padding(.vertical, 14)
            .transition(.opacity)
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
        } else if loadingRelations {
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
        } else if loadingRelations {
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

    private func chipColumn(_ title: String, _ items: [String]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            SecLabel(title)
            FlowLayout(spacing: 6) {
                ForEach(items, id: \.self) { InteractiveChip(text: $0, language: entry.language) }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: Bottom bar

    private var bottomBar: some View {
        VStack(spacing: 0) {
            Hairline()
            HStack {
                if let app = entry.sourceApp {
                    Text("Source: \(app)\(entry.sourceURL.map { " · \($0)" } ?? "")")
                        .font(.system(size: 12)).foregroundStyle(Theme.textTertiary).lineLimit(1)
                }
                Spacer()
                Button { PracticePresenter.shared.present(entry: entry) } label: {
                    Label(L.t("Practice writing", "Luyện viết"), systemImage: "pencil.line")
                }
                .buttonStyle(.vPrimary)
            }
            .padding(.horizontal, 14).padding(.vertical, 10)
            .background(Theme.bgSecondary)
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
