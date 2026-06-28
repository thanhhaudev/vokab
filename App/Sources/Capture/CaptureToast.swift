import SwiftUI
import AppKit
import VokabKit

/// State for the capture toast (SPEC §12 surface #7).
@MainActor
final class ToastModel: ObservableObject {
    enum Phase: Equatable {
        case analyzing(String)
        case resolved(entry: Entry?, fallback: String, wasDuplicate: Bool)
        case error(String)
        /// A standalone, self-dismissing message (no actions) — used by detail-screen
        /// actions like "+ add example" / reload to confirm success or report a no-op.
        case notice(text: String, danger: Bool)
    }
    @Published var phase: Phase = .analyzing("") {
        didSet {
            switch phase {
            case .resolved, .error, .notice: if resolvedAt == nil { resolvedAt = Date() }
            case .analyzing: resolvedAt = nil
            }
            onResize?()
        }
    }
    /// When this toast was created — drives the live elapsed-time label.
    let createdAt = Date()
    /// When the toast resolved/errored — the elapsed label freezes here.
    private(set) var resolvedAt: Date?
    var meaningLanguage = "vi"
    var onView: (() -> Void)?
    var onUndo: ((Int64) -> Void)?
    /// Set when an inflected capture was resolved to its lemma (e.g. "running"→"run").
    /// Drives the "captured X → Y" line and the "Keep original" action.
    var lemmaRename: (surface: String, headword: String)?
    /// Re-captures the original surface form as its own entry (Keep original).
    var onKeepOriginal: (() -> Void)?
    /// Set on an alias-duplicate (homograph) toast — re-captures the surface as its own entry.
    var onSaveSeparately: (() -> Void)?
    /// Called when `phase` changes so the host panel can re-fit its height.
    var onResize: (() -> Void)?
}

/// The toast content, matching the mockup: app icon, status, word + pills.
struct CaptureToastView: View {
    @Environment(\.displayScale) private var displayScale
    @ObservedObject var model: ToastModel

    var body: some View {
        HStack(alignment: .top, spacing: 11) {
            appIcon
            VStack(alignment: .leading, spacing: 0) { content }
                .frame(maxWidth: .infinity, alignment: .leading)   // bounds FlowLayout so rows wrap, not squish
            if showsElapsed { elapsedLabel }
        }
        .padding(.horizontal, 14).padding(.vertical, 12)
        .frame(width: 344, alignment: .leading)
        .background(Theme.bgPrimary, in: RoundedRectangle(cornerRadius: Theme.radiusLg))
        .overlay(RoundedRectangle(cornerRadius: Theme.radiusLg).strokeBorder(Theme.borderTertiary, lineWidth: Theme.hairline(displayScale)))
    }

    private var appIcon: some View {
        BrandBadge(size: 38, corner: 9)
    }

    /// The elapsed-time label is meaningful only for a capture's lifecycle, not a
    /// standalone notice.
    private var showsElapsed: Bool {
        if case .notice = model.phase { return false }
        return true
    }

    @ViewBuilder private var content: some View {
        switch model.phase {
        case .analyzing(let text):
            HStack(spacing: 7) {
                Text("vokab").font(.system(size: 13, weight: .medium))
                ActivityDots()
            }
            Text("\(L.t("Analyzing", "Đang phân tích")) \u{201C}\(text)\u{201D}")
                .font(.system(size: 13)).foregroundStyle(Theme.textSecondary)
                .lineLimit(3)
                .padding(.top, 2)

        case .resolved(let entry, let fallback, let wasDuplicate):
            HStack(spacing: 6) {
                Text(wasDuplicate ? L.t("Already in vokab", "Đã có trong vokab")
                                  : L.t("Added to vokab", "Đã thêm vào vokab"))
                    .font(.system(size: 13, weight: .medium))
                Image(systemName: wasDuplicate ? "checkmark.circle" : "checkmark")
                    .font(.system(size: 11))
                    .foregroundStyle(wasDuplicate ? Theme.textTertiary : Theme.diffIns)
            }
            if let entry {
                resolvedEntry(entry)
            } else {
                Text(fallback).font(.system(size: 13)).foregroundStyle(Theme.textSecondary).padding(.top, 3)
            }
            actions(entryId: entry?.id, wasDuplicate: wasDuplicate)

        case .error(let message):
            Text(L.t("Capture failed", "Bắt từ thất bại")).font(.system(size: 13, weight: .medium)).foregroundStyle(Theme.textDanger)
            Text(message).font(.system(size: 12)).foregroundStyle(Theme.textSecondary).padding(.top, 2).lineLimit(2)

        case .notice(let text, let danger):
            HStack(spacing: 6) {
                Image(systemName: danger ? "exclamationmark.triangle" : "checkmark.circle")
                    .font(.system(size: 11))
                    .foregroundStyle(danger ? Theme.textDanger : Theme.diffIns)
                Text(text)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(danger ? Theme.textDanger : Theme.textPrimary)
                    .lineLimit(2)
            }
        }
    }

    @ViewBuilder private func resolvedEntry(_ entry: Entry) -> some View {
        let summary = CardDecoding.summary(entry, meaningLanguage: model.meaningLanguage)
        // Wrapping row (mockup #7): word + CEFR + category pill. pos lives in the
        // meaning line below, not here.
        FlowLayout(spacing: 6) {
            Text(entry.rawText).font(.system(size: 14, weight: .medium)).lineLimit(1)
            if let cefr = summary.cefr { Pill.cefr(cefr) }
            if let category = entry.category {
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
        }
        .padding(.top, 4)
        if let r = model.lemmaRename {
            Text(L.t("captured \u{201C}\(r.surface)\u{201D} \u{2192} \(r.headword)", "đã bắt \u{201C}\(r.surface)\u{201D} \u{2192} \(r.headword)"))
                .font(.system(size: 11)).foregroundStyle(Theme.textTertiary).padding(.top, 3).lineLimit(1)
        }
        if let meaning = summary.meaning {
            Text(meaning + (summary.pos.map { " · \($0)" } ?? ""))
                .font(.system(size: 12)).foregroundStyle(Theme.textSecondary).padding(.top, 3).lineLimit(1)
        }
    }

    @ViewBuilder private func actions(entryId: Int64?, wasDuplicate: Bool) -> some View {
        HStack(spacing: 7) {
            toastAction(L.t("View", "Xem"), system: "eye", primary: true) { model.onView?() }
            // Undo deletes the entry by id. For a duplicate that id is the user's
            // pre-existing entry — undoing would destroy original data — so only
            // offer Undo for a genuinely new capture.
            if let entryId, !wasDuplicate {
                toastAction(L.t("Undo", "Hoàn tác"), system: "arrow.uturn.backward", primary: false) { model.onUndo?(entryId) }
            }
            if model.lemmaRename != nil, let keep = model.onKeepOriginal {
                toastAction(L.t("Keep original", "Giữ nguyên gốc"), system: "textformat", primary: false) { keep() }
            }
            if let save = model.onSaveSeparately {
                toastAction(L.t("Save separately", "Lưu riêng"), system: "rectangle.badge.plus", primary: false) { save() }
            }
        }
        .padding(.top, 10)
    }

    private func toastAction(_ title: String, system: String, primary: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label(title, systemImage: system).font(.system(size: 12, weight: primary ? .medium : .regular))
                .padding(.horizontal, 12).padding(.vertical, 5)
                .background(primary ? Theme.accentBg : Theme.bgPrimary, in: RoundedRectangle(cornerRadius: Theme.radiusMd))
                .overlay(RoundedRectangle(cornerRadius: Theme.radiusMd)
                    .strokeBorder(primary ? .clear : Theme.borderSecondary, lineWidth: Theme.hairline(displayScale)))
                .foregroundStyle(primary ? Theme.accentText : Theme.textPrimary)
        }
        .buttonStyle(.plain)
    }

    /// Live elapsed-time since the toast was created ("now", "5s", "2m"),
    /// ticking every second via TimelineView.
    private var elapsedLabel: some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            Text(elapsedString(now: context.date))
                .font(.system(size: 11)).foregroundStyle(Theme.textTertiary)
                .monospacedDigit()
        }
    }

    private func elapsedString(now: Date) -> String {
        // Freeze at the resolution moment; tick live while still analyzing.
        let end = model.resolvedAt ?? now
        let seconds = max(0, Int(end.timeIntervalSince(model.createdAt)))
        if seconds < 1 { return "now" }
        if seconds < 60 { return "\(seconds)s" }
        return "\(seconds / 60)m"
    }
}

// Toast presentation is handled by `ToastCenter` (multi-panel stack).
