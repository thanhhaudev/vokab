import SwiftUI
import AppKit
import VokabKit

/// Explains one inflected form (role, IPA, gloss, usage note, common error, examples)
/// with a one-tap path to the lemma's full detail. Opened from a Forms chip.
struct FormInfoPopover: View {
    @EnvironmentObject private var env: AppEnvironment
    let form: WordForm
    let headword: String
    let language: String
    let lemmaEntryId: Int64?
    /// True while the card is (en)riching/backfilling — so a bare form shows a
    /// loading hint instead of just "form of X".
    var loading: Bool = false

    /// Whether the form carries the meaningful per-form content (not just IPA).
    private var hasDetail: Bool {
        (form.gloss?.isEmpty == false) || (form.usageNote?.isEmpty == false)
            || (form.commonError?.isEmpty == false) || !form.examples.isEmpty
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            // Word + pronounce on the top row; role and IPA each on their own line
            // below. The role is plain wrapping text, NOT a fixed-size Pill — agy's
            // role labels can be phrase-length ("Past / Past participle (irregular)")
            // and a Pill would balloon and squeeze the word into wrapping.
            HStack(spacing: 8) {
                Text(form.form).font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Theme.textPrimary).lineLimit(1)
                Spacer(minLength: 8)
                PronounceButton(text: form.form,
                                accent: Accent(settingsValue: env.settings.pronunciationAccent), size: .small)
            }
            if !form.label.isEmpty {
                Text(form.label)
                    .font(.system(size: 12, weight: .medium)).foregroundStyle(Theme.accent)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if let ipa = form.ipa, !ipa.isEmpty {
                Text(ipa).font(Theme.mono(12)).foregroundStyle(Theme.textSecondary).lineLimit(1)
            }
            Button {
                if let id = lemmaEntryId { WindowManager.shared.showLibrary(select: id) }
            } label: {
                Text(L.t("form of \(headword)", "dạng của \(headword)"))
                    .font(.system(size: 12)).foregroundStyle(Theme.accent)
            }
            .buttonStyle(.plain)
            if !hasDetail && loading {
                HStack(spacing: 7) {
                    ActivityDots(diameter: 4)
                    Text(L.t("Loading…", "Đang tải nghĩa…"))
                        .font(.system(size: 12)).foregroundStyle(Theme.textTertiary)
                }
            }
            if let gloss = form.gloss, !gloss.isEmpty {
                Text(gloss).font(.system(size: 13)).foregroundStyle(Theme.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if let note = form.usageNote, !note.isEmpty {
                Text(note).font(.system(size: 12)).foregroundStyle(Theme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if let err = form.commonError, !err.isEmpty {
                Label(err, systemImage: "xmark.circle")
                    .font(.system(size: 12)).foregroundStyle(Theme.textDanger)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if !form.examples.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    SecLabel(L.t("Examples", "Ví dụ"))
                    ForEach(form.examples.prefix(2), id: \.self) { ex in
                        HStack(alignment: .firstTextBaseline, spacing: 6) {
                            Text(ex).font(.system(size: 12)).italic().foregroundStyle(Theme.textSecondary)
                                .fixedSize(horizontal: false, vertical: true)
                            PronounceButton(text: ex,
                                            accent: Accent(settingsValue: env.settings.pronunciationAccent), size: .small)
                        }
                    }
                }
            }
        }
        .padding(14)
        .frame(width: 300, alignment: .leading)
        .background(Theme.bgPrimary)
    }
}

/// A neutral Forms chip that opens a FormInfoPopover on tap.
struct FormChip: View {
    @Environment(\.displayScale) private var displayScale
    @EnvironmentObject private var env: AppEnvironment
    let form: WordForm
    let headword: String
    let language: String
    let lemmaEntryId: Int64?
    var loading: Bool = false
    @State private var showing = false
    @State private var hovering = false

    var body: some View {
        HStack(spacing: 5) {
            Text(form.form).font(.system(size: 12))
            if !form.label.isEmpty {
                Text("· \(form.label)").font(.system(size: 11)).foregroundStyle(Theme.textTertiary)
            }
        }
        .padding(.horizontal, 10).padding(.vertical, 4)
        .background(Theme.bgPrimary, in: Capsule())
        .overlay(Capsule().strokeBorder(hovering ? Theme.accent : Theme.borderSecondary,
                                        lineWidth: Theme.hairline(displayScale)))
        .foregroundStyle(Theme.textSecondary)
        .contentShape(Capsule())
        .onHover { h in hovering = h; if h { NSCursor.pointingHand.push() } else { NSCursor.pop() } }
        .onTapGesture { showing = true }
        .popover(isPresented: $showing, arrowEdge: .bottom) {
            FormInfoPopover(form: form, headword: headword, language: language,
                            lemmaEntryId: lemmaEntryId, loading: loading)
                .environmentObject(env)
        }
    }
}
