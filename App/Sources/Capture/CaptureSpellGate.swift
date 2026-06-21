import SwiftUI
import VokabKit

/// Shared pre-capture warning: amber chips for fixable typos (and word-shaped
/// "no suggestion" items), plus a distinct red banner for words that don't look
/// real. Never blocks — `onCaptureAnyway` always lets the user proceed.
struct CaptureSpellGate: View {
    let issues: [SpellCheck.Issue]
    let onFixAll: () -> Void
    let onFixOne: (SpellCheck.Issue) -> Void
    let onCaptureAnyway: () -> Void

    private var typos: [SpellCheck.Issue] { issues.filter { $0.kind != .nonexistent } }
    private var nonexistent: [SpellCheck.Issue] { issues.filter { $0.kind == .nonexistent } }
    private var hasFixable: Bool { typos.contains { $0.suggestion != nil } }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if !typos.isEmpty { typoBlock }
            if !nonexistent.isEmpty { nonexistentBlock }
        }
    }

    // MARK: Amber typo block (existing behavior)
    private var typoBlock: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: "exclamationmark.bubble").font(.system(size: 11)).foregroundStyle(.orange)
                Text(L.t("Possible typos", "Có thể sai chính tả"))
                    .font(.system(size: 11)).foregroundStyle(Theme.textSecondary)
                Spacer()
                if hasFixable {
                    Button(L.t("Fix all", "Sửa hết"), action: onFixAll)
                        .buttonStyle(.plain).font(.system(size: 11, weight: .medium)).foregroundStyle(Theme.accent)
                    Text("·").font(.system(size: 11)).foregroundStyle(Theme.textTertiary)
                }
                Button(L.t("Capture anyway", "Lưu nguyên"), action: onCaptureAnyway)
                    .buttonStyle(.plain).font(.system(size: 11)).foregroundStyle(Theme.textSecondary)
            }
            FlowLayout(spacing: 6) {
                ForEach(typos) { issue in
                    Button { if issue.suggestion != nil { onFixOne(issue) } } label: {
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

    // MARK: Red "not a real word" block (new)
    private var nonexistentBlock: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: "exclamationmark.octagon").font(.system(size: 11)).foregroundStyle(.red)
                Text(L.t("Not a real word", "Không phải từ có thật"))
                    .font(.system(size: 11, weight: .medium)).foregroundStyle(.red)
                Spacer()
                Button(L.t("Capture anyway", "Lưu nguyên"), action: onCaptureAnyway)
                    .buttonStyle(.plain).font(.system(size: 11)).foregroundStyle(Theme.textSecondary)
            }
            FlowLayout(spacing: 6) {
                ForEach(nonexistent) { issue in
                    Text(issue.word)
                        .font(.system(size: 11)).foregroundStyle(.red)
                        .padding(.horizontal, 7).padding(.vertical, 3)
                        .background(Color.red.opacity(0.08), in: Capsule())
                        .overlay(Capsule().strokeBorder(Color.red.opacity(0.4), lineWidth: Theme.hairline))
                }
            }
            Text(L.t("Analyzing it still spends an agy call / quota.",
                     "Vẫn tốn một lượt agy / quota để phân tích."))
                .font(.system(size: 10)).foregroundStyle(Theme.textTertiary)
        }
        .padding(8)
        .background(Color.red.opacity(0.06), in: RoundedRectangle(cornerRadius: 6))
    }
}
