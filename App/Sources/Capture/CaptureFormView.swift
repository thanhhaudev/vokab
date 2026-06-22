import SwiftUI
import AppKit
import VokabKit

/// In-Library capture form (mockup #10): collapsed one-line `.rform` when idle;
/// on focus it expands (accent border + glow) to show the detected type pill,
/// a word count, a language dropdown, a functional [Auto|Word|Phrase] override,
/// and a Capture button. Enter captures.
struct CaptureFormView: View {
    @Environment(\.displayScale) private var displayScale
    @State private var text = ""
    @FocusState private var focused: Bool
    @State private var typeChoice: TypeChoice = .auto
    @State private var langOverride: String?
    @State private var spellIssues: [SpellCheck.Issue] = []
    @State private var forceSubmit = false
    /// Set right before a programmatic text edit so the text change below doesn't wipe chips.
    @State private var suppressSpellReset = false
    private var isParagraph: Bool { effectiveType == .paragraphItem }

    private var trimmed: String { text.trimmingCharacters(in: .whitespacesAndNewlines) }
    private var effectiveType: CardType { typeChoice.forcedType ?? CaptureDetection.type(text) }
    private var detectedLang: String { CaptureDetection.language(text) }
    private var wordCount: Int? {
        guard effectiveType != .word else { return nil }
        let n = trimmed.split(whereSeparator: { $0 == " " || $0 == "\n" }).count
        return n > 1 ? n : nil
    }
    private var active: Bool { focused && !trimmed.isEmpty }

    var body: some View {
        VStack(spacing: 0) {
            HStack(alignment: .top, spacing: 8) {
                Image(systemName: "plus").font(.system(size: 15)).foregroundStyle(Theme.accent)
                    .padding(.top, 1)
                // Grows like a textarea: a pasted sentence wraps onto multiple lines.
                TextField(L.t("Enter a word or phrase…", "Nhập từ hoặc cụm từ…"), text: $text, axis: .vertical)
                    .textFieldStyle(.plain).font(.system(size: 14)).lineLimit(1...6).focused($focused)
                    .onSubmit(submit)
                    .onChange(of: text) { _, _ in
                        if suppressSpellReset { suppressSpellReset = false; return }
                        spellIssues = []; forceSubmit = false
                    }
                Button(action: paste) {
                    Image(systemName: "doc.on.clipboard").font(.system(size: 11)).foregroundStyle(Theme.textTertiary)
                        .frame(width: 26, height: 20)   // fixed size so it matches the ⏎ badge exactly
                        .background(Theme.bgSecondary, in: RoundedRectangle(cornerRadius: 5))
                        .overlay(RoundedRectangle(cornerRadius: 5).strokeBorder(Theme.borderTertiary, lineWidth: Theme.hairline(displayScale)))
                }
                .buttonStyle(.plain).help(L.t("Paste from clipboard", "Dán từ clipboard"))
                if !active {
                    Text("⏎").font(Theme.mono(11)).foregroundStyle(Theme.textTertiary)
                        .frame(width: 26, height: 20)
                        .background(Theme.bgSecondary, in: RoundedRectangle(cornerRadius: 5))
                        .overlay(RoundedRectangle(cornerRadius: 5).strokeBorder(Theme.borderTertiary, lineWidth: Theme.hairline(displayScale)))
                }
            }
            .padding(.horizontal, 11).padding(.vertical, 9)

            if active {
                Rectangle().fill(Theme.borderTertiary).frame(height: Theme.hairline(displayScale))
                HStack(spacing: 8) {
                    Text(L.t("Detected", "Nhận diện")).font(.system(size: 10)).foregroundStyle(Theme.textTertiary)
                    DetectedTypePill(type: effectiveType, count: wordCount)
                    Spacer()
                    LanguageMenu(selection: $langOverride, detected: detectedLang)
                }
                .padding(.horizontal, 14).padding(.vertical, 9)

                HStack(spacing: 8) {
                    TypeOverrideSegmented(choices: [.auto, .word, .phrase], selection: $typeChoice)
                    Spacer()
                    Button(action: submit) {
                        HStack(spacing: 4) {
                            Image(systemName: "return"); Text(L.t("Capture", "Lưu"))
                        }
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(Theme.accentBg)
                        .padding(.horizontal, 11).padding(.vertical, 5)
                        .background(Theme.accent, in: RoundedRectangle(cornerRadius: 6))
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, 11).padding(.bottom, 10)

                Text(L.t("Override type with the segmented control · ⏎ to capture",
                         "Override loại bằng segmented · ⏎ capture"))
                    .font(.system(size: 10)).foregroundStyle(Theme.textTertiary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 11).padding(.bottom, 9)

                if !spellIssues.isEmpty {
                    CaptureSpellGate(
                        issues: spellIssues,
                        onFixAll: {
                            suppressSpellReset = true
                            text = SpellCheck.fixAll(text, issues: spellIssues); spellIssues = []
                        },
                        onFixOne: { issue in
                            suppressSpellReset = true
                            text = SpellCheck.fixAll(text, issues: [issue])
                            spellIssues.removeAll { $0.id == issue.id }
                        },
                        onCaptureAnyway: { forceSubmit = true; submit() }
                    )
                    .padding(.horizontal, 11).padding(.bottom, 10)
                }
            }
        }
        .background(Theme.bgSecondary)
        .clipShape(RoundedRectangle(cornerRadius: Theme.radiusMd))
        .overlay(
            RoundedRectangle(cornerRadius: Theme.radiusMd)
                .strokeBorder(active ? Theme.accent : Theme.borderTertiary, lineWidth: active ? 1 : Theme.hairline(displayScale))
        )
        .shadow(color: active ? Theme.accent.opacity(0.18) : .clear, radius: 2.5)   // mockup .rform.active glow
        .animation(.easeOut(duration: 0.15), value: active)
        .onChange(of: active) { _, isActive in
            if !isActive { typeChoice = .auto; langOverride = nil }   // don't carry a stale override
        }
    }

    private func submit() {
        guard !trimmed.isEmpty else { return }
        // Local spell/gibberish gate (word & phrase only). Paragraphs are word
        // harvests full of proper nouns — checking them is just noise.
        if !forceSubmit && !isParagraph {
            let issues = SpellCheck.issues(in: trimmed, language: detectedLang)
            if !issues.isEmpty { spellIssues = issues; return }   // show gate, don't submit yet
        }
        CaptureController.shared.capture(trimmed, source: SourceContext(appName: "Manual entry"),
                                         language: langOverride, type: typeChoice.forcedType)
        text = ""; typeChoice = .auto; langOverride = nil; focused = false
        spellIssues = []; forceSubmit = false
    }

    /// Replaces the field with the clipboard's text and focuses it (so a pasted
    /// long sentence lands ready to capture).
    private func paste() {
        guard let s = NSPasteboard.general.string(forType: .string) else { return }
        text = s
        focused = true
    }
}
