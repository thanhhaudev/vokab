import SwiftUI
import AppKit
import UniformTypeIdentifiers
import VokabKit

/// A small floating capture field shown by the global hotkey. Enter captures
/// (as a manual entry), Esc dismisses.
@MainActor
final class QuickCapture {
    static let shared = QuickCapture()
    private var panel: NSPanel?

    func show(prefill: String? = nil) {
        // Seed the field with the auto-grabbed selection, else the clipboard, so
        // the flow is "select → hotkey → Enter" (a Services-menu replacement).
        // Recreated each open because a cached panel's SwiftUI @State wouldn't refresh.
        let seed = prefill ?? (NSPasteboard.general.string(forType: .string)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? "")
        panel?.orderOut(nil)
        let panel = makePanel(initialText: seed)
        self.panel = panel
        reposition(panel)
        // A non-activating panel can take key focus without activating the whole
        // app — so other open vokab windows (e.g. Settings) are NOT pulled forward.
        panel.makeKeyAndOrderFront(nil)
        panel.orderFrontRegardless()
    }

    func hide() { panel?.orderOut(nil) }

    private func makePanel(initialText: String) -> NSPanel {
        let src = SourceContext(appName: "Manual entry")
        // The header pill should show the user's ACTUAL global hotkey (or nothing
        // when it's not enabled) — not a hardcoded string.
        let hotkeyLabel: String? = {
            guard let s = AppEnvironment.shared?.settings,
                  s.globalHotkeyEnabled, s.globalHotkeyKeyCode != 0 else { return nil }
            return GlobalHotkey.label(keyCode: s.globalHotkeyKeyCode, modifiers: s.globalHotkeyModifiers)
        }()
        let view = QuickCaptureView(initialText: initialText, hotkeyLabel: hotkeyLabel, onSubmit: { [weak self] text, language, type, minLevel in
            CaptureController.shared.capture(text, source: src,
                                             language: language, type: type, minLevel: minLevel)
            self?.hide()
        }, onBatch: { [weak self] lines in
            WindowManager.shared.showBatch(lines: lines, source: src)
            self?.hide()
        }, onCancel: { [weak self] in self?.hide() })

        let hosting = NSHostingView(rootView: view)
        hosting.frame = NSRect(x: 0, y: 0, width: 680, height: 240)
        let panel = NSPanel(contentRect: hosting.frame,
                            styleMask: [.titled, .closable, .nonactivatingPanel, .fullSizeContentView],
                            backing: .buffered, defer: false)
        panel.titleVisibility = .hidden
        panel.titlebarAppearsTransparent = true
        panel.isFloatingPanel = true
        panel.level = .floating
        panel.contentView = hosting
        panel.isMovableByWindowBackground = true
        return panel
    }

    private func reposition(_ panel: NSPanel) {
        guard let screen = NSScreen.main else { return }
        let vf = screen.visibleFrame
        let size = panel.frame.size
        panel.setFrameOrigin(NSPoint(x: vf.midX - size.width / 2, y: vf.midY + 120))
    }
}

private struct QuickCaptureView: View {
    let hotkeyLabel: String?
    let onSubmit: (String, String?, CardType?, CEFR?) -> Void
    let onBatch: ([String]) -> Void
    let onCancel: () -> Void
    @State private var text: String
    @State private var typeChoice: TypeChoice = .auto
    @State private var minLevel: CEFR = .b2
    @FocusState private var focused: Bool
    @State private var spellIssues: [SpellCheck.Issue] = []
    @State private var forceSubmit = false
    /// Set right before a programmatic text edit (chip fix / Fix all) so the
    /// text `onChange` below doesn't wipe the remaining chips.
    @State private var suppressSpellReset = false

    init(initialText: String = "", hotkeyLabel: String? = nil,
         onSubmit: @escaping (String, String?, CardType?, CEFR?) -> Void,
         onBatch: @escaping ([String]) -> Void, onCancel: @escaping () -> Void) {
        self.hotkeyLabel = hotkeyLabel
        self.onSubmit = onSubmit
        self.onBatch = onBatch
        self.onCancel = onCancel
        _text = State(initialValue: initialText)
    }

    private var trimmed: String { text.trimmingCharacters(in: .whitespacesAndNewlines) }
    private var effectiveType: CardType { typeChoice.forcedType ?? CaptureDetection.type(text) }
    private var detectedLang: String { CaptureDetection.language(text) }
    private var wordCount: Int? {
        guard effectiveType != .word else { return nil }
        let n = trimmed.split(whereSeparator: { $0 == " " || $0 == "\n" }).count
        return n > 1 ? n : nil
    }
    private var isParagraph: Bool { effectiveType == .paragraphItem }
    private var lines: [String] {
        trimmed.split(whereSeparator: \.isNewline)
            .map { String($0).trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
    }
    private var isBatch: Bool { lines.count >= 2 && !isParagraph }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Text("V").font(.system(size: 13, weight: .bold)).foregroundStyle(Theme.accentBg)
                    .frame(width: 24, height: 24).background(Theme.accent, in: RoundedRectangle(cornerRadius: 6))
                Text(L.t("Quick Capture", "Quick Capture")).font(.system(size: 12, weight: .medium))
                    .foregroundStyle(Theme.textSecondary)
                Spacer()
                if let hotkeyLabel {
                    Text(hotkeyLabel).font(Theme.mono(11)).foregroundStyle(Theme.textTertiary)
                        .padding(.horizontal, 6).padding(.vertical, 2)
                        .background(Theme.bgSecondary, in: RoundedRectangle(cornerRadius: 5))
                        .overlay(RoundedRectangle(cornerRadius: 5).strokeBorder(Theme.borderTertiary, lineWidth: Theme.hairline))
                        .help(L.t("Global hotkey to open Quick Capture (set in Settings)",
                                  "Phím tắt toàn cục mở Quick Capture (đặt trong Settings)"))
                }
            }

            // MARK: Multi-line TextEditor with placeholder overlay + drag-drop
            ZStack(alignment: .topLeading) {
                if text.isEmpty {
                    Text(L.t("Type or paste… (drag text or .txt here)",
                             "Gõ hoặc dán… (kéo thả text/file .txt vào)"))
                        .font(.system(size: 16)).foregroundStyle(Theme.textTertiary)
                        .padding(.top, 1).padding(.leading, 5).allowsHitTesting(false)
                }
                TextEditor(text: $text)
                    .font(.system(size: 16)).focused($focused)
                    .scrollContentBackground(.hidden)
                    .frame(minHeight: 44, maxHeight: 140)
            }
            .onChange(of: text) { _, _ in
                // A programmatic chip/Fix-all edit must NOT wipe the other chips;
                // only a real user edit resets the spell state.
                if suppressSpellReset { suppressSpellReset = false; return }
                spellIssues = []; forceSubmit = false
            }
            .onDrop(of: [.fileURL, .text, .plainText, .utf8PlainText], isTargeted: nil) { providers in
                handleDrop(providers)
            }

            // Single row — the panel is wide enough to fit Paragraph mode's
            // Min-level menu + segmented; fixedSize labels never wrap.
            HStack(spacing: 8) {
                detectedCluster
                Spacer()
                trailingControls
            }

            // MARK: Spell-check confirm gate (shown only when issues detected)
            if !spellIssues.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 6) {
                        Image(systemName: "exclamationmark.bubble").font(.system(size: 11)).foregroundStyle(.orange)
                        Text(L.t("Possible typos", "Có thể sai chính tả"))
                            .font(.system(size: 11)).foregroundStyle(Theme.textSecondary)
                        Spacer()
                        if spellIssues.contains(where: { $0.suggestion != nil }) {
                            Button(L.t("Fix all", "Sửa hết")) {
                                suppressSpellReset = true
                                text = SpellCheck.fixAll(text, issues: spellIssues); spellIssues = []
                            }.buttonStyle(.plain).font(.system(size: 11, weight: .medium)).foregroundStyle(Theme.accent)
                            Text("·").font(.system(size: 11)).foregroundStyle(Theme.textTertiary)
                        }
                        Button(L.t("Capture anyway", "Lưu nguyên")) {
                            forceSubmit = true; submit()
                        }.buttonStyle(.plain).font(.system(size: 11)).foregroundStyle(Theme.textSecondary)
                    }
                    // Each misspelled word is a chip "word → suggestion"; click to fix just that one.
                    FlowLayout(spacing: 6) {
                        ForEach(spellIssues) { issue in
                            Button {
                                guard issue.suggestion != nil else { return }
                                suppressSpellReset = true
                                text = SpellCheck.fixAll(text, issues: [issue])
                                spellIssues.removeAll { $0.id == issue.id }
                            } label: {
                                HStack(spacing: 4) {
                                    Text(issue.word).foregroundStyle(.orange)
                                    if let s = issue.suggestion {
                                        Image(systemName: "arrow.right").font(.system(size: 7)).foregroundStyle(Theme.textTertiary)
                                        Text(s).foregroundStyle(Theme.textPrimary)
                                    }
                                }
                                .font(.system(size: 11))
                                .padding(.horizontal, 7).padding(.vertical, 3)
                                .background(Theme.bgPrimary, in: Capsule())
                                .overlay(Capsule().strokeBorder(Theme.borderTertiary, lineWidth: Theme.hairline))
                            }
                            .buttonStyle(.plain)
                            .disabled(issue.suggestion == nil)
                            .help(issue.suggestion != nil ? L.t("Click to fix", "Bấm để sửa từ này")
                                                          : L.t("No suggestion", "Không có gợi ý"))
                        }
                    }
                }
                .padding(8)
                .background(Theme.bgTertiary, in: RoundedRectangle(cornerRadius: 6))
            }

            HStack(spacing: 6) {
                Text(L.t("Press", "Nhấn")).font(.system(size: 12)).foregroundStyle(Theme.textSecondary)
                Text("⌘↵").font(Theme.mono(11)).foregroundStyle(Theme.textTertiary)
                    .padding(.horizontal, 5).padding(.vertical, 1)
                    .background(Theme.bgSecondary, in: RoundedRectangle(cornerRadius: 4))
                Text(isBatch ? L.t("to review", "để xem") :
                     isParagraph ? L.t("to extract", "để trích xuất") : L.t("to capture", "để lưu"))
                    .font(.system(size: 12)).foregroundStyle(Theme.textSecondary)
                Text("· Esc").font(.system(size: 11)).foregroundStyle(Theme.textTertiary)
                Spacer()
                Button(action: submit) {
                    HStack(spacing: 5) {
                        Text(isBatch ? L.t("Review \(lines.count) items", "Xem \(lines.count) mục") :
                             isParagraph ? L.t("Capture & extract", "Lưu & trích") : L.t("Capture", "Lưu"))
                            .font(.system(size: 12, weight: .medium))
                        // Show the real shortcut (⌘↵) — plain ↵ inserts a newline.
                        Text("⌘↵").font(Theme.mono(11)).opacity(0.85)
                    }
                    .foregroundStyle(Theme.accentBg)
                    .padding(.horizontal, 11).padding(.vertical, 5)
                    .background(Theme.accent, in: RoundedRectangle(cornerRadius: 6))
                }
                .buttonStyle(.plain)
                .keyboardShortcut(.return, modifiers: .command)
                .help(L.t("Capture (⌘↵). Enter adds a new line.",
                          "Lưu (⌘↵). Enter để xuống dòng."))
            }
        }
        .padding(16)
        .frame(width: 680, alignment: .leading)
        .background(Theme.bgPrimary)
        .onAppear { focused = true }   // text is seeded from the clipboard via init
        .onExitCommand { onCancel() }
    }

    /// "Detected:" label + type pill (+ passive language pill when not paragraph).
    /// Both texts are `fixedSize` so they never wrap letter-by-letter.
    @ViewBuilder private var detectedCluster: some View {
        HStack(spacing: 8) {
            Text(L.t("Detected:", "Nhận diện:")).font(.system(size: 11))
                .foregroundStyle(Theme.textTertiary).fixedSize()
            DetectedTypePill(type: effectiveType, count: wordCount)
            if !isParagraph {
                // Passive language pill (mockup #9 shows "English (auto)", not a dropdown).
                Text("\(detectedLang.uppercased()) (\(L.t("auto", "auto")))")
                    .font(.system(size: 11)).foregroundStyle(Theme.textSecondary)
                    .padding(.horizontal, 8).padding(.vertical, 3)
                    .background(Theme.bgTertiary, in: Capsule())
                    .fixedSize()
            }
        }
    }

    /// Min-level menu (paragraph only) + the type override segmented control.
    @ViewBuilder private var trailingControls: some View {
        HStack(spacing: 8) {
            if isParagraph {
                Menu {
                    ForEach(CEFR.allCases, id: \.self) { lvl in
                        Button(lvl.rawValue.uppercased()) { minLevel = lvl }
                    }
                } label: {
                    HStack(spacing: 3) {
                        Text(L.t("Min level: \(minLevel.rawValue.uppercased())",
                                 "Min level: \(minLevel.rawValue.uppercased())"))
                        Image(systemName: "chevron.down").font(.system(size: 9))
                    }
                    .font(.system(size: 11)).foregroundStyle(Theme.accent)
                }
                .menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize()
            }
            // Segmented stays visible in every mode so the user can always
            // switch back out of Para (avoids a one-way trap).
            TypeOverrideSegmented(choices: [.auto, .word, .phrase, .paragraph], selection: $typeChoice)
        }
    }

    // MARK: Submit

    private func submit() {
        let captured = trimmed                 // snapshot BEFORE clearing text
        guard !captured.isEmpty else { return }
        // Spell-check gate: word/phrase/batch only. Paragraphs go to extraction
        // (you're harvesting words, not the sentence) and are full of proper nouns
        // — checking them just produces noise, so skip.
        if !forceSubmit && !isParagraph {
            let issues = SpellCheck.issues(in: captured, language: detectedLang)
            if !issues.isEmpty { spellIssues = issues; return }   // show confirm, don't submit yet
        }
        // Batch path: multi-line non-paragraph → open dedupe checklist
        if isBatch {
            let items = lines
            text = ""; typeChoice = .auto; minLevel = .b2; spellIssues = []; forceSubmit = false
            onBatch(items)
            return
        }
        // proceed (existing behavior)
        let type = typeChoice.forcedType
        let lvl: CEFR? = isParagraph ? minLevel : nil
        text = ""; typeChoice = .auto; minLevel = .b2; spellIssues = []; forceSubmit = false
        onSubmit(captured, nil, type, lvl)     // #9 language is auto-only (mockup)
    }

    // MARK: Drag-drop

    private func handleDrop(_ providers: [NSItemProvider]) -> Bool {
        var handled = false
        for p in providers {
            if p.canLoadObject(ofClass: URL.self) {
                handled = true
                _ = p.loadObject(ofClass: URL.self) { url, _ in
                    guard let url, url.isFileURL,
                          let s = try? String(contentsOf: url, encoding: .utf8) else { return }
                    DispatchQueue.main.async { appendDropped(s) }
                }
            } else if p.canLoadObject(ofClass: NSString.self) {
                handled = true
                _ = p.loadObject(ofClass: NSString.self) { obj, _ in
                    guard let s = obj as? String else { return }
                    DispatchQueue.main.async { appendDropped(s) }
                }
            }
        }
        return handled
    }

    private func appendDropped(_ s: String) {
        let t = s.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !t.isEmpty else { return }
        text = text.isEmpty ? t : text + "\n" + t
    }
}
