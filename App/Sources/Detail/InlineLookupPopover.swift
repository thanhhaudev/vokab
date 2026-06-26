import SwiftUI
import VokabKit

/// Popover shown when a word/phrase on the detail screen is clicked.
/// SAVED → a menubar-style mini-card (DueDot + word + cefr, meaning · pos, "Mở chi tiết");
/// NOT SAVED → a Capture button running the optimistic pipeline. The capturing window
/// folds into the saved card: the entry inserts immediately and the card shows a
/// skeleton meaning + spinner while agy analyzes, then the fields pop in. No agy call
/// is made just to preview.
struct InlineLookupPopover: View {
    @EnvironmentObject private var env: AppEnvironment
    let text: String
    /// `.word` for a single token, `.phrase` for a multi-word span.
    let hint: CardType
    let language: String

    private enum State: Equatable { case loading, notSaved, saved(Entry) }
    @SwiftUI.State private var state: State = .loading
    @SwiftUI.State private var dueStatus: Theme.DueStatus = .new
    /// True from tapping Capture until the inserted entry first resolves, so a
    /// transient `find` miss doesn't flip the card back to `.notSaved`.
    @SwiftUI.State private var pendingCapture = false
    @SwiftUI.State private var captureHover = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            switch state {
            case .loading:      loading
            case .notSaved:     notSaved
            case .saved(let e): saved(e)
            }
        }
        .frame(width: 280)
        .background(Theme.bgPrimary)
        .onAppear(perform: resolve)
        .onReceive(NotificationCenter.default.publisher(for: WindowManager.dataDidChange)) { _ in resolve() }
    }

    // MARK: States

    private var loading: some View {
        ProgressView().controlSize(.small)
            .frame(maxWidth: .infinity, alignment: .center)
            .padding(.horizontal, 14).padding(.vertical, 16)
    }

    private var notSaved: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 8) {
                Text(text).font(.system(size: 15, weight: .medium)).foregroundStyle(Theme.textPrimary)
                    .lineLimit(2).fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
                Text(L.t("not saved", "chưa lưu"))
                    .font(.system(size: 11)).foregroundStyle(Theme.textTertiary)
            }
            .padding(.horizontal, 14).padding(.vertical, 12)
            Hairline()
            Button {
                pendingCapture = true
                CaptureController.shared.capture(text, language: language, type: hint)
            } label: {
                HStack(spacing: 9) {
                    Image(systemName: "plus.circle").font(.system(size: 14))
                    Text(L.t("Add to library", "Lưu vào thư viện")).font(.system(size: 13, weight: .medium))
                    Spacer(minLength: 0)
                }
                .foregroundStyle(Theme.accent)
                .padding(.horizontal, 14).padding(.vertical, 10)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(captureHover ? Theme.accent.opacity(0.12) : Color.clear)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .onHover { captureHover = $0 }
        }
    }

    private func saved(_ entry: Entry) -> some View {
        let analyzing = entry.analysisState == AnalysisState.analyzing.rawValue
        let failed = entry.analysisState == AnalysisState.failed.rawValue
        let s = CardDecoding.summary(entry, meaningLanguage: env.settings.meaningLanguage)
        return VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 8) {
                    DueDot(status: dueStatus)
                    Text(entry.rawText).font(.system(size: 14, weight: .medium)).foregroundStyle(Theme.textPrimary)
                        .lineLimit(1)
                    if let cefr = s.cefr { Pill.cefr(cefr) }
                    Spacer(minLength: 0)
                    if analyzing { ProgressView().controlSize(.small) }
                }
                if failed {
                    Label(L.t("Analysis failed", "Phân tích thất bại"), systemImage: "exclamationmark.triangle")
                        .font(.system(size: 12)).foregroundStyle(Theme.textSecondary)
                } else if analyzing {
                    Text("Đang phân tích nghĩa của từ")
                        .font(.system(size: 12)).foregroundStyle(Theme.textSecondary)
                        .skeleton()
                } else if let meaning = s.meaning {
                    Text(meaning + (s.pos.map { " · \($0)" } ?? ""))
                        .font(.system(size: 12)).foregroundStyle(Theme.textSecondary)
                        .lineLimit(2).fixedSize(horizontal: false, vertical: true)
                    if let category = entry.category { categoryPill(category) }
                }
            }
            .padding(.horizontal, 14).padding(.vertical, 12)
            Hairline()
            Button {
                WindowManager.shared.showLibrary(select: entry.id)
            } label: {
                Label(L.t("Open detail", "Mở chi tiết"), systemImage: "arrow.up.right.square")
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .buttonStyle(.vSecondary)
            .padding(.horizontal, 14).padding(.vertical, 10)
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
