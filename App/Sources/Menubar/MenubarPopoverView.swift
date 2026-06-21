import SwiftUI
import AppKit
import VokabKit

/// Menubar popover (SPEC §12 surface #8).
struct MenubarPopoverView: View {
    @EnvironmentObject var env: AppEnvironment

    @State private var dueCount = 0
    @State private var nextDue: [LibraryRow] = []
    @State private var weekAdded = 0
    @State private var reviewed = 0
    @State private var streak = 0
    @State private var captureText = ""
    @FocusState private var captureFocused: Bool
    @State private var flashWord: String?
    @State private var flashTask: Task<Void, Never>?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Hairline()
            if nextDue.isEmpty {
                Text(L.t("Nothing due. Nice work.", "Không có từ đến hạn. Tốt lắm."))
                    .font(.system(size: 13)).foregroundStyle(Theme.textSecondary)
                    .padding(.horizontal, 14).padding(.vertical, 12)
            } else {
                ForEach(nextDue.prefix(3)) { row in dueRow(row) }
                if dueCount > 3 {
                    Text(L.t("+ \(dueCount - 3) more…", "+ \(dueCount - 3) từ nữa…"))
                        .font(.system(size: 11)).foregroundStyle(Theme.textTertiary)
                        .padding(.horizontal, 14).padding(.top, 4).padding(.bottom, 2)
                }
            }

            Button { WindowManager.shared.showReview() } label: {
                Label(dueCount > 0 ? L.t("Review now", "Ôn tập ngay")
                                   : L.t("Study ahead", "Ôn sớm"),
                      systemImage: "play.fill").frame(maxWidth: .infinity)
            }
            .buttonStyle(.vPrimary)
            .padding(.horizontal, 14).padding(.top, 10).padding(.bottom, 4)

            Hairline().padding(.top, 8)
            footer
            Hairline()
            captureField
        }
        .frame(width: 300)
        .background(Theme.bgPrimary)
        .onAppear(perform: reload)
        .onReceive(NotificationCenter.default.publisher(for: WindowManager.dataDidChange)) { _ in
            reload()
        }
    }

    private var header: some View {
        HStack(alignment: .lastTextBaseline, spacing: 8) {
            Text("\(dueCount)").font(.system(size: 22, weight: .medium)).foregroundStyle(Theme.textPrimary)
            Text(L.t("due today", "từ đến hạn hôm nay")).font(.system(size: 13)).foregroundStyle(Theme.textSecondary)
            Spacer()
            if streak > 0 {
                Label("\(streak) \(L.t("days", "ngày"))", systemImage: "flame")
                    .font(.system(size: 12)).foregroundStyle(Theme.textTertiary)
            }
        }
        .padding(.horizontal, 14).padding(.top, 12).padding(.bottom, 8)
    }

    private func dueRow(_ row: LibraryRow) -> some View {
        HStack(spacing: 9) {
            DueDot(status: row.dueStatus)
            Text(row.entry.rawText).font(.system(size: 13, weight: .medium))
                .frame(maxWidth: .infinity, alignment: .leading).lineLimit(1)
            if let cefr = row.entry.cefr { Pill.cefr(cefr) }
        }
        .padding(.horizontal, 14).padding(.vertical, 8)
        .contentShape(Rectangle())
        .onTapGesture { WindowManager.shared.showLibrary() }
    }

    private var footer: some View {
        HStack {
            Text(L.t("This week: +\(weekAdded) · reviewed \(reviewed)",
                     "Tuần này: +\(weekAdded) từ · đã ôn \(reviewed)"))
                .font(.system(size: 11)).foregroundStyle(Theme.textTertiary)
            Spacer()
            Button { WindowManager.shared.showLibrary() } label: {
                HStack(spacing: 4) { Text(L.t("Open Library", "Mở Library")); Image(systemName: "arrow.up.right.square") }
                    .font(.system(size: 12)).foregroundStyle(Theme.accent)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 14).padding(.vertical, 9)
    }

    private var captureField: some View {
        VStack(alignment: .leading, spacing: 6) {
            // Optimistic flash: mirrors the corner toast's "analyzing" phase.
            // The toast owns the real outcome (resolved / duplicate / error);
            // this just confirms the submit while the popover is still open.
            if let flashWord {
                HStack(spacing: 5) {
                    Image(systemName: "sparkles").font(.system(size: 10))
                    Text(L.t("Analyzing \"\(flashWord)\"…", "Đang phân tích \"\(flashWord)\"…"))
                        .font(.system(size: 11)).lineLimit(1)
                }
                .foregroundStyle(Theme.dueColor(.new))
                .transition(.opacity)
            }

            HStack(spacing: 8) {
                Image(systemName: "plus").font(.system(size: 13)).foregroundStyle(Theme.accent)
                TextField(L.t("Capture a word…", "Bắt một từ…"), text: $captureText)
                    .textFieldStyle(.plain).font(.system(size: 13))
                    .focused($captureFocused)
                    .onSubmit(runCapture)
                // ⏎ hint: dimmed while empty so it only lights up when actionable.
                Text("⏎").font(Theme.mono(11)).foregroundStyle(Theme.textTertiary)
                    .frame(width: 26, height: 20)
                    .background(Theme.bgSecondary, in: RoundedRectangle(cornerRadius: 5))
                    .overlay(RoundedRectangle(cornerRadius: 5)
                        .strokeBorder(Theme.borderTertiary, lineWidth: Theme.hairline))
                    .opacity(captureText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? 0.4 : 1)
            }
            .padding(.horizontal, 10).padding(.vertical, 7)
            .background(Theme.bgPrimary, in: RoundedRectangle(cornerRadius: Theme.radiusMd))
            .overlay(
                RoundedRectangle(cornerRadius: Theme.radiusMd)
                    .strokeBorder(captureFocused ? Theme.accent : Theme.borderTertiary,
                                  lineWidth: captureFocused ? 1 : Theme.hairline)
            )
            .shadow(color: captureFocused ? Theme.accent.opacity(0.18) : .clear, radius: 2.5)
            .animation(.easeOut(duration: 0.15), value: captureFocused)
        }
        .padding(.horizontal, 14).padding(.vertical, 9)
        .background(Theme.bgSecondary)
        .animation(.easeOut(duration: 0.15), value: flashWord)
    }

    private func runCapture() {
        let text = captureText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        captureText = ""
        CaptureController.shared.capture(text, source: SourceContext(appName: "Manual entry"))
        // The capture is async; CaptureController posts dataDidChange on success,
        // which reloads this popover (see .onReceive above). The corner toast owns
        // the durable result — this inline flash is optimistic and short-lived.
        flashWord = text
        captureFocused = true                       // keep focus for rapid adds
        flashTask?.cancel()
        flashTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 1_200_000_000)   // ~1.2s
            if !Task.isCancelled { flashWord = nil }
        }
    }

    private func reload() {
        let now = Date()
        dueCount = (try? env.review.dueCount(on: now)) ?? 0
        let cards = (try? env.review.dueCards(on: now)) ?? []
        nextDue = cards.map { LibraryRow(entry: $0.entry, dueStatus: .today, intervalLabel: "today",
                                         meaning: nil, cefr: $0.entry.cefr) }
        let all = (try? env.entries.all()) ?? []
        let weekAgo = now.addingTimeInterval(-7 * 86_400)
        weekAdded = all.filter { $0.capturedAt >= weekAgo }.count
        reviewed = all.compactMap { $0.id }
            .compactMap { try? env.review.state(entryId: $0) }
            .reduce(0) { $0 + $1.reviewCount }
        streak = (try? env.reviewLog.streak()) ?? 0
    }
}
