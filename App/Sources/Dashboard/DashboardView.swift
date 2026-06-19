import SwiftUI
import VokabKit

/// App "home" surface: a header, the capture form as a centered hero, a wrapping
/// row of stat tiles, and three insight charts (activity, due forecast, library
/// composition). Not wired into a window yet — that's a separate task. Reuses
/// `Theme` tokens and existing components (CaptureFormView, DailyLimitRing,
/// FlowLayout) so it matches the Library's visual language.
struct DashboardView: View {
    let env: AppEnvironment
    @ObservedObject var model: LibraryViewModel

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                header
                captureHero
                statTiles
                activitySection
                forecastSection
                librarySection
            }
            .padding(24)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(Theme.bgPrimary)
        .onAppear { model.load() }
    }

    // MARK: Header

    private var header: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(L.t("Dashboard", "Bảng điều khiển"))
                .font(.system(size: 22, weight: .semibold))
                .foregroundStyle(Theme.textPrimary)
            Text(Date().formatted(.dateTime.weekday(.wide).day().month(.wide)))
                .font(.system(size: 12))
                .foregroundStyle(Theme.textTertiary)
        }
    }

    // MARK: Capture hero

    private var captureHero: some View {
        HStack {
            Spacer()
            CaptureFormView().frame(maxWidth: 560)
            Spacer()
        }
    }

    // MARK: Stat tiles

    private var statTiles: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 116), spacing: 12)], spacing: 12) {
            StatTile(value: "\(model.dueCount)",
                     label: L.t("Due today", "Đến hạn"),
                     accent: model.overdueCount > 0 ? .red : Theme.accent)
            StatTile(value: "\(model.reviewedToday)",
                     label: L.t("Reviewed today", "Đã ôn hôm nay"),
                     accent: Theme.accent)
            StatTile(value: "🔥 \(model.streak)",
                     label: L.t("Streak", "Chuỗi"),
                     accent: Theme.textPrimary)
            StatTile(value: "\(model.total)",
                     label: L.t("Words", "Số từ"),
                     accent: Theme.textPrimary)
            StatTile(value: model.diskLabel,
                     label: L.t("Disk", "Ổ đĩa"),
                     accent: Theme.textSecondary)
            StatTile(value: "\(model.quotaUsed)/\(model.quotaLimit)",
                     label: L.t("Quota", "Hạn mức"),
                     accent: Theme.accent,
                     ring: model.quotaLimit > 0 ? Double(model.quotaUsed) / Double(model.quotaLimit) : 0,
                     ringUsed: model.quotaUsed,
                     ringLimit: model.quotaLimit)
        }
    }

    // MARK: Sections

    private var activitySection: some View {
        section(L.t("Activity", "Hoạt động")) {
            VStack(alignment: .leading, spacing: 8) {
                BarRow(values: model.activity)
                Text(L.t("\(model.activity.reduce(0, +)) reviews · last 8 weeks",
                         "\(model.activity.reduce(0, +)) lượt ôn · 8 tuần gần đây"))
                    .font(.system(size: 11))
                    .foregroundStyle(Theme.textTertiary)
            }
        }
    }

    private var forecastSection: some View {
        section(L.t("Due forecast", "Dự báo đến hạn")) {
            VStack(alignment: .leading, spacing: 8) {
                ForecastBars(values: model.forecast)
                Text(L.t("next 14 days", "14 ngày tới"))
                    .font(.system(size: 11))
                    .foregroundStyle(Theme.textTertiary)
            }
        }
    }

    private var librarySection: some View {
        section(L.t("Library", "Thư viện")) {
            VStack(alignment: .leading, spacing: 16) {
                if !model.cefrComposition.isEmpty {
                    compositionGroup(L.t("Level", "Cấp độ"), rows: cefrRows)
                }
                if model.languageComposition.count > 1 {
                    compositionGroup(L.t("Language", "Ngôn ngữ"), rows: languageRows)
                }
                if !model.topCategories.isEmpty {
                    compositionGroup(L.t("Categories", "Chủ đề"), rows: categoryRows)
                }
            }
        }
    }

    // MARK: Composition data → colored rows

    private var cefrRows: [(label: String, count: Int, color: Color)] {
        model.cefrComposition.map { item in
            (item.label, item.count, PillStyle.cefrColors(item.label).fg)
        }
    }

    private var languageRows: [(label: String, count: Int, color: Color)] {
        model.languageComposition.map { ($0.label, $0.count, Theme.accent) }
    }

    private var categoryRows: [(label: String, count: Int, color: Color)] {
        model.topCategories.map { item in
            let color = model.categoryColorIndex[item.label].map { Theme.categoryColor($0) } ?? Theme.accent
            return (item.label, item.count, color)
        }
    }

    // MARK: Section chrome

    @ViewBuilder
    private func section<Content: View>(_ title: String,
                                        @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            SecLabel(title)
            content()
                .padding(14)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Theme.bgSecondary, in: RoundedRectangle(cornerRadius: Theme.radiusMd))
                .overlay(RoundedRectangle(cornerRadius: Theme.radiusMd)
                    .strokeBorder(Theme.borderTertiary, lineWidth: Theme.hairline))
        }
    }

    @ViewBuilder
    private func compositionGroup(_ title: String,
                                  rows: [(label: String, count: Int, color: Color)]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(Theme.textSecondary)
            CompositionBars(rows: rows)
        }
    }
}
