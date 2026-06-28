import SwiftUI
import VokabKit

/// Popover shown when a word/phrase on the detail screen is clicked.
/// SAVED → a rich peek card: header (DueDot + word + IPA + pronounce), a level +
/// category row under the word, then labelled NGHĨA / VÍ DỤ / ĐỒNG NGHĨA sections,
/// and a flat "Open detail" row. Phrases fall back to a labelled meaning line.
/// NOT SAVED → a single, snug, content-sized "Add to library" row. The capturing
/// window folds into the saved card (skeleton + spinner while agy analyzes). No agy
/// call is made just to preview.
struct InlineLookupPopover: View {
    @EnvironmentObject private var env: AppEnvironment
    let text: String
    /// `.word` for a single token, `.phrase` for a multi-word span.
    let hint: CardType
    let language: String

    private enum State: Equatable { case notSaved, saved(Entry) }
    @SwiftUI.State private var state: State = .notSaved
    @SwiftUI.State private var dueStatus: Theme.DueStatus = .new
    /// True from tapping Capture until the inserted entry first resolves, so a
    /// transient `find` miss doesn't flip the card back to `.notSaved`.
    @SwiftUI.State private var pendingCapture = false
    @SwiftUI.State private var captureHover = false
    @SwiftUI.State private var detailHover = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            switch state {
            case .notSaved:     notSaved
            case .saved(let e): saved(e)
            }
        }
        .background(Theme.bgPrimary)
        .onAppear(perform: resolve)
        .onReceive(NotificationCenter.default.publisher(for: WindowManager.dataDidChange)) { _ in resolve() }
    }

    // MARK: States

    /// Compact, content-sized single action row — clicking the word already says
    /// which word it is, so no header is shown.
    private var notSaved: some View {
        Button {
            pendingCapture = true
            CaptureController.shared.capture(text, language: language, type: hint)
        } label: {
            HStack(spacing: 9) {
                Image(systemName: "plus.circle").font(.system(size: 14))
                Text(L.t("Add to library", "Lưu vào thư viện")).font(.system(size: 13, weight: .medium))
            }
            .fixedSize()
            .foregroundStyle(Theme.accent)
            .padding(.horizontal, 16).padding(.vertical, 11)
            .background(captureHover ? Theme.accent.opacity(0.12) : Color.clear)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { captureHover = $0 }
    }

    private func saved(_ entry: Entry) -> some View {
        let analyzing = entry.analysisState == AnalysisState.analyzing.rawValue
        let failed = entry.analysisState == AnalysisState.failed.rawValue
        let card = entry.cardType == .word ? CardDecoding.word(entry) : nil
        let s = CardDecoding.summary(entry, meaningLanguage: env.settings.meaningLanguage)
        return VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 9) {
                // Header: dot + word + IPA + pronounce (+ spinner while analyzing).
                HStack(spacing: 8) {
                    DueDot(status: dueStatus)
                    Text(entry.rawText).font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(Theme.textPrimary).lineLimit(1)
                    if let ipa = card?.ipa, !ipa.isEmpty {
                        Text(ipa).font(Theme.mono(12)).foregroundStyle(Theme.textSecondary).lineLimit(1)
                    }
                    PronounceButton(text: entry.rawText,
                                    accent: Accent(settingsValue: env.settings.pronunciationAccent),
                                    size: .small)
                    Spacer(minLength: 0)
                    if analyzing { ActivityDots(diameter: 4) }
                }
                // Level + category, under the word.
                if s.cefr != nil || entry.category != nil {
                    HStack(spacing: 6) {
                        if let cefr = s.cefr { Pill.cefr(cefr) }
                        if let category = entry.category { categoryPill(category) }
                    }
                }
                // Body sections.
                if failed {
                    Label(L.t("Analysis failed", "Phân tích thất bại"), systemImage: "exclamationmark.triangle")
                        .font(.system(size: 12)).foregroundStyle(Theme.textSecondary)
                } else if analyzing {
                    Text("Đang phân tích nghĩa của từ")
                        .font(.system(size: 12)).foregroundStyle(Theme.textSecondary).skeleton()
                } else if let card, entry.cardType == .word {
                    wordBody(card)
                } else if let meaning = s.meaning {
                    section(L.t("Meaning", "Nghĩa")) {
                        Text(meaning + (s.pos.map { " · \($0)" } ?? ""))
                            .font(.system(size: 13)).foregroundStyle(Theme.textPrimary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
            .padding(.horizontal, 14).padding(.vertical, 12)
            Hairline()
            // Flat "Open detail" row — no nested bordered button (no card-in-card).
            Button {
                WindowManager.shared.showLibrary(select: entry.id)
            } label: {
                HStack(spacing: 9) {
                    Image(systemName: "arrow.up.right.square").font(.system(size: 13))
                    Text(L.t("Open detail", "Mở chi tiết")).font(.system(size: 13, weight: .medium))
                    Spacer(minLength: 0)
                }
                .foregroundStyle(Theme.accent)
                .padding(.horizontal, 14).padding(.vertical, 11)
                .background(detailHover ? Theme.accent.opacity(0.12) : Color.clear)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .onHover { detailHover = $0 }
        }
        .frame(width: 300)
    }

    /// The rich word body: labelled senses, example, synonyms.
    @ViewBuilder private func wordBody(_ card: WordCard) -> some View {
        section(L.t("Meanings", "Nghĩa")) {
            ForEach(Array(card.resolvedSenses.enumerated()), id: \.offset) { _, sense in
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    if let pos = sense.pos { Pill(pos, style: .type) }
                    if let g = card.gloss(sense, forLanguage: env.settings.meaningLanguage) {
                        Text(g).font(.system(size: 13)).foregroundStyle(Theme.textPrimary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
        }
        if let eg = card.examples.first ?? card.resolvedSenses.first?.examples.first, !eg.isEmpty {
            section(L.t("Example", "Ví dụ")) {
                Text(eg).font(.system(size: 12)).italic().foregroundStyle(Theme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.leading, 9)
                    .overlay(alignment: .leading) { Rectangle().fill(Theme.borderSecondary).frame(width: 2) }
            }
        }
        if !card.synonyms.isEmpty {
            section(L.t("Synonyms", "Đồng nghĩa")) {
                FlowLayout(spacing: 6) {
                    ForEach(card.synonyms.prefix(4), id: \.self) { Chip($0) }
                }
            }
        }
    }

    /// A labelled section: small uppercase label + its content.
    @ViewBuilder private func section<Content: View>(_ label: String,
                                                     @ViewBuilder _ content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            SecLabel(label)
            content()
        }
    }

    /// Toast-style category chip (teal save tokens).
    private func categoryPill(_ category: String) -> some View {
        HStack(spacing: 4) {
            Image(systemName: "folder").font(.system(size: 10))
            Text(category).lineLimit(1)
        }
        .font(.system(size: 11, weight: .medium))
        .foregroundStyle(Theme.saveFg)
        .padding(.horizontal, 7).padding(.vertical, 3)
        .background(Theme.saveBg, in: Capsule())
        .fixedSize()
    }

    // MARK: Lookup

    private func resolve() {
        if let entry = try? env.entries.find(rawText: text, language: language) {
            let st = entry.id.flatMap { try? env.review.state(entryId: $0) }
            dueStatus = Theme.DueStatus.of(st, now: Date())
            state = .saved(entry)
        } else if !pendingCapture {
            // No entry yet and we're not mid-capture → offer Capture.
            state = .notSaved
        }
        // miss + pendingCapture → keep the current (optimistic/loading) state until
        // the inserted entry appears via dataDidChange.
    }
}
