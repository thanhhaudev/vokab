import SwiftUI
import VokabKit

/// The Library window's home: a warm greeting and the capture composer as the
/// single hero, plus a one-line "review due" call to action. All counts and
/// breakdowns live in the sidebar, so the dashboard stays focused on the two
/// things you actually do here — capture a word, and review what's due.
struct DashboardView: View {
    let env: AppEnvironment
    @ObservedObject var model: LibraryViewModel

    var body: some View {
        GeometryReader { geo in
            ScrollView {
                VStack(spacing: 0) {
                    Spacer(minLength: 40)
                    hero
                    Spacer(minLength: 40)
                }
                .frame(maxWidth: .infinity)
                .frame(minHeight: geo.size.height)
                .padding(.horizontal, 28)
            }
        }
        .background(Theme.bgPrimary)
        .onAppear { model.load() }
    }

    private var hero: some View {
        VStack(spacing: 20) {
            VStack(spacing: 6) {
                Text(Date().formatted(.dateTime.weekday(.wide).day().month(.wide)).uppercased())
                    .font(.system(size: 11, weight: .medium)).tracking(0.7)
                    .foregroundStyle(Theme.textTertiary)
                Text(greeting)
                    .font(.system(size: 26, weight: .medium))
                    .foregroundStyle(Theme.textPrimary)
            }
            CaptureFormView()
                .frame(maxWidth: 600)
            reviewCTA
        }
        .frame(maxWidth: .infinity)
    }

    /// A quiet call to action: jump into review when cards are due, else a calm
    /// "all caught up". Not a stat card — the count lives in the sidebar; this is
    /// the action.
    @ViewBuilder
    private var reviewCTA: some View {
        if model.dueCount > 0 {
            Button { CaptureController.shared.openReview() } label: {
                HStack(spacing: 6) {
                    Text(L.t("\(model.dueCount) due today", "\(model.dueCount) thẻ đến hạn"))
                        .font(.system(size: 13, weight: .medium))
                    Image(systemName: "arrow.right").font(.system(size: 11, weight: .semibold))
                }
                .foregroundStyle(Theme.accentText)
                .padding(.horizontal, 14).padding(.vertical, 7)
                .background(Theme.accentBg, in: Capsule())
            }
            .buttonStyle(.plain)
            .help(L.t("Start reviewing", "Bắt đầu ôn"))
        } else {
            Text(L.t("You're all caught up for today", "Hôm nay đã ôn xong"))
                .font(.system(size: 12))
                .foregroundStyle(Theme.textTertiary)
        }
    }

    /// Time-of-day greeting — the page's single bold moment.
    private var greeting: String {
        switch Calendar.current.component(.hour, from: Date()) {
        case 5..<12:  return L.t("Good morning", "Chào buổi sáng")
        case 12..<18: return L.t("Good afternoon", "Chào buổi chiều")
        default:      return L.t("Good evening", "Chào buổi tối")
        }
    }
}
