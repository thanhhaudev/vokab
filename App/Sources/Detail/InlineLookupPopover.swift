import SwiftUI
import VokabKit

/// Popover shown when a word/phrase on the detail screen is clicked. Two states:
/// SAVED → a mini-card with "open detail"; NOT SAVED → a Capture button that runs
/// the existing optimistic capture pipeline. No agy call is made just to preview.
struct InlineLookupPopover: View {
    @EnvironmentObject private var env: AppEnvironment
    let text: String
    /// `.word` for a single token, `.phrase` for a multi-word span.
    let hint: CardType
    let language: String

    private enum State: Equatable { case loading, saved(Entry), notSaved, capturing }
    @SwiftUI.State private var state: State = .loading

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            switch state {
            case .loading:    ProgressView().controlSize(.small)
            case .notSaved:   notSaved
            case .capturing:  capturing
            case .saved(let e): saved(e)
            }
        }
        .padding(12)
        .frame(width: 260)
        .onAppear(perform: resolve)
        .onReceive(NotificationCenter.default.publisher(for: WindowManager.dataDidChange)) { _ in resolve() }
    }

    // MARK: States

    private var notSaved: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(text).font(.system(size: 15, weight: .medium)).foregroundStyle(Theme.textPrimary)
            Button {
                state = .capturing
                CaptureController.shared.capture(text, language: language, type: hint)
            } label: {
                Label(L.t("Capture", "Lưu lại"), systemImage: "plus.circle")
            }
            .buttonStyle(.vPrimary)
        }
    }

    private var capturing: some View {
        HStack(spacing: 8) {
            ProgressView().controlSize(.small)
            Text(L.t("Saving…", "Đang xử lý…")).font(.system(size: 13)).foregroundStyle(Theme.textSecondary)
        }
    }

    private func saved(_ entry: Entry) -> some View {
        let s = CardDecoding.summary(entry, meaningLanguage: env.settings.meaningLanguage)
        return VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Text(entry.rawText).font(.system(size: 15, weight: .medium)).foregroundStyle(Theme.textPrimary)
                if let pos = s.pos { MultiPill(pos, style: .type) }
                if let cefr = s.cefr { Pill.cefr(cefr) }
            }
            if let meaning = s.meaning {
                Text(meaning).font(.system(size: 13)).foregroundStyle(Theme.textSecondary)
            }
            Button {
                WindowManager.shared.showLibrary(select: entry.id)
            } label: {
                Label(L.t("Open detail", "Mở chi tiết"), systemImage: "arrow.up.right.square")
            }
            .buttonStyle(.vSecondary)
        }
    }

    // MARK: Lookup

    private func resolve() {
        if let entry = try? env.entries.find(rawText: text, language: language) {
            state = .saved(entry)
        } else if state != .capturing {
            // Stay in `.capturing` until the new entry shows up via dataDidChange.
            state = .notSaved
        }
    }
}
