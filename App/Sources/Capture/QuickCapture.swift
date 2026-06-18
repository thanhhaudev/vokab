import SwiftUI
import AppKit
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
        let view = QuickCaptureView(initialText: initialText, onSubmit: { [weak self] text, language, type, minLevel in
            CaptureController.shared.capture(text, source: SourceContext(appName: "Manual entry"),
                                             language: language, type: type, minLevel: minLevel)
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
    let onSubmit: (String, String?, CardType?, CEFR?) -> Void
    let onCancel: () -> Void
    @State private var text: String
    @State private var typeChoice: TypeChoice = .auto
    @State private var minLevel: CEFR = .b2
    @FocusState private var focused: Bool

    init(initialText: String = "", onSubmit: @escaping (String, String?, CardType?, CEFR?) -> Void,
         onCancel: @escaping () -> Void) {
        self.onSubmit = onSubmit
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

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Text("V").font(.system(size: 13, weight: .bold)).foregroundStyle(Theme.accentBg)
                    .frame(width: 24, height: 24).background(Theme.accent, in: RoundedRectangle(cornerRadius: 6))
                Text(L.t("Quick Capture", "Quick Capture")).font(.system(size: 12, weight: .medium))
                    .foregroundStyle(Theme.textSecondary)
                Spacer()
                Text("⌃⌥Space").font(Theme.mono(11)).foregroundStyle(Theme.textTertiary)
                    .padding(.horizontal, 6).padding(.vertical, 2)
                    .background(Theme.bgSecondary, in: RoundedRectangle(cornerRadius: 5))
                    .overlay(RoundedRectangle(cornerRadius: 5).strokeBorder(Theme.borderTertiary, lineWidth: Theme.hairline))
            }

            TextField(L.t("Type or paste…", "Gõ hoặc dán…"), text: $text, axis: .vertical)
                .textFieldStyle(.plain).font(.system(size: 16)).focused($focused)
                .lineLimit(1...3)
                .onSubmit(submit)

            // Single row — the panel is wide enough to fit Paragraph mode's
            // Min-level menu + segmented; fixedSize labels never wrap.
            HStack(spacing: 8) {
                detectedCluster
                Spacer()
                trailingControls
            }

            HStack(spacing: 6) {
                Text(L.t("Press", "Nhấn")).font(.system(size: 12)).foregroundStyle(Theme.textSecondary)
                Text("↵").font(Theme.mono(11)).foregroundStyle(Theme.textTertiary)
                    .padding(.horizontal, 5).padding(.vertical, 1)
                    .background(Theme.bgSecondary, in: RoundedRectangle(cornerRadius: 4))
                Text(isParagraph ? L.t("to extract", "để trích xuất") : L.t("to capture", "để lưu"))
                    .font(.system(size: 12)).foregroundStyle(Theme.textSecondary)
                Text("· Esc").font(.system(size: 11)).foregroundStyle(Theme.textTertiary)
                Spacer()
                Button(action: submit) {
                    HStack(spacing: 4) {
                        Text(isParagraph ? L.t("Capture & extract", "Lưu & trích") : L.t("Capture", "Lưu"))
                        Image(systemName: "return")
                    }
                    .font(.system(size: 12, weight: .medium)).foregroundStyle(Theme.accentBg)
                    .padding(.horizontal, 11).padding(.vertical, 5)
                    .background(Theme.accent, in: RoundedRectangle(cornerRadius: 6))
                }
                .buttonStyle(.plain)
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

    private func submit() {
        let captured = trimmed                 // snapshot BEFORE clearing text
        guard !captured.isEmpty else { return }
        let type = typeChoice.forcedType
        let lvl: CEFR? = isParagraph ? minLevel : nil
        text = ""; typeChoice = .auto; minLevel = .b2
        onSubmit(captured, nil, type, lvl)     // #9 language is auto-only (mockup)
    }
}
