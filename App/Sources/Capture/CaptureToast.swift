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
    }
    @Published var phase: Phase = .analyzing("") {
        didSet {
            switch phase {
            case .resolved, .error: if resolvedAt == nil { resolvedAt = Date() }
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
    /// Called when `phase` changes so the host panel can re-fit its height.
    var onResize: (() -> Void)?
}

/// The toast content, matching the mockup: app icon, status, word + pills.
struct CaptureToastView: View {
    @ObservedObject var model: ToastModel

    var body: some View {
        HStack(alignment: .top, spacing: 11) {
            appIcon
            VStack(alignment: .leading, spacing: 0) { content }
                .frame(maxWidth: .infinity, alignment: .leading)   // bounds FlowLayout so rows wrap, not squish
            elapsedLabel
        }
        .padding(.horizontal, 14).padding(.vertical, 12)
        .frame(width: 344, alignment: .leading)
        .background(Theme.bgPrimary, in: RoundedRectangle(cornerRadius: Theme.radiusLg))
        .overlay(RoundedRectangle(cornerRadius: Theme.radiusLg).strokeBorder(Theme.borderTertiary, lineWidth: Theme.hairline))
    }

    private var appIcon: some View {
        Text("V")
            .font(.system(size: 20, weight: .medium)).foregroundStyle(Theme.accentBg)
            .frame(width: 38, height: 38)
            .background(Theme.accent, in: RoundedRectangle(cornerRadius: 9))
    }

    @ViewBuilder private var content: some View {
        switch model.phase {
        case .analyzing(let text):
            HStack(spacing: 7) {
                Text("vokab").font(.system(size: 13, weight: .medium))
                PulsingDots()
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
                .foregroundStyle(Color(hex: 0x085041))
                .padding(.horizontal, 7).padding(.vertical, 3)
                .background(Color(hex: 0xE1F5EE), in: Capsule())
                .fixedSize()
            }
        }
        .padding(.top, 4)
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
        }
        .padding(.top, 10)
    }

    private func toastAction(_ title: String, system: String, primary: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label(title, systemImage: system).font(.system(size: 12, weight: primary ? .medium : .regular))
                .padding(.horizontal, 12).padding(.vertical, 5)
                .background(primary ? Theme.accentBg : Theme.bgPrimary, in: RoundedRectangle(cornerRadius: Theme.radiusMd))
                .overlay(RoundedRectangle(cornerRadius: Theme.radiusMd)
                    .strokeBorder(primary ? .clear : Theme.borderSecondary, lineWidth: Theme.hairline))
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

/// Three dots that gently fade in a staggered wave (opacity only — no movement)
/// for the analyzing state. The classic "typing…" indicator. Honors Reduce Motion.
struct PulsingDots: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var animating = false

    private let count = 3
    private let dot: CGFloat = 5
    private let period = 0.5
    private let stagger = 0.16

    var body: some View {
        HStack(spacing: 4) {
            ForEach(0..<count, id: \.self) { i in
                Circle()
                    .fill(Color(hex: 0x7F77DD))
                    .frame(width: dot, height: dot)
                    .opacity(animating ? 1.0 : 0.25)
                    .animation(
                        reduceMotion ? nil :
                            .easeInOut(duration: period)
                            .repeatForever(autoreverses: true)
                            .delay(Double(i) * stagger),
                        value: animating)
            }
        }
        .frame(height: dot)
        .onAppear { animating = true }
    }
}

// Toast presentation is handled by `ToastCenter` (multi-panel stack).
