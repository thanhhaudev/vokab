import SwiftUI
import VokabKit

/// Main Library window (SPEC §12 surface #4): fixed sidebar with nav + level +
/// language filters, metric cards, and a due-dot list. Selecting a row opens the
/// matching detail (word/phrase/paragraph) as a sheet.
struct LibraryView: View {
    @EnvironmentObject var env: AppEnvironment
    @StateObject private var model: LibraryViewModel
    @State private var selected: Entry?
    @State private var search = ""
    @State private var pendingDelete: Entry?
    @State private var showAllCategories = false
    @State private var showDashboard = true
    // Persisted across launches; the live @State values drive layout during a
    // drag so we don't write UserDefaults every frame (that caused jank).
    @AppStorage("library.sidebarWidth") private var storedSidebarWidth: Double = 172
    @AppStorage("library.mainWidth") private var storedMainWidth: Double = 320
    @State private var sidebarWidth: Double = 172
    @State private var mainWidth: Double = 320
    @State private var reloadPulse = false
    @State private var showCooldownNote = false

    /// Categories shown before the "+N more" cap (mockup #4 shows the top 5).
    private static let categoryCap = 5

    /// Due-today card dot: red when anything is overdue, else amber (state-dot palette).
    private var dueAccent: Color {
        model.overdueCount > 0 ? Color(hex: 0xD85A30) : Color(hex: 0xEF9F27)
    }

    init(env: AppEnvironment) {
        _model = StateObject(wrappedValue: LibraryViewModel(env: env))
    }

    var body: some View {
        GeometryReader { geo in
            // Clamp stored widths to the actual window so the panes never overflow
            // (overflow centred the HStack and clipped the sidebar's left edge).
            // detail takes whatever remains (>= ~200) and the row pins leading so
            // the sidebar is never cut off.
            let gap: CGFloat = 12               // two dividers
            let avail = geo.size.width
            let sw = max(150, min(CGFloat(sidebarWidth), avail - gap - 240 - 200))
            let mw = max(240, min(CGFloat(mainWidth), avail - gap - sw - 200))
            HStack(spacing: 0) {
                sidebar.frame(width: sw)
                ResizableDivider(width: $sidebarWidth, range: 150...300) { storedSidebarWidth = $0 }
                if showDashboard {
                    DashboardView(env: env, model: model)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    main.frame(width: mw)
                    ResizableDivider(width: $mainWidth, range: 240...640) { storedMainWidth = $0 }
                    detailPane.frame(maxWidth: .infinity)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        }
        .background(Theme.bgPrimary)
        .onAppear {
            model.load()
            sidebarWidth = storedSidebarWidth
            mainWidth = storedMainWidth
            // A freshly opened Library may have been asked to focus a specific entry.
            if let id = WindowManager.shared.consumePendingSelection() {
                selected = (try? env.entries.entry(id: id)) ?? nil
                showDashboard = false
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: WindowManager.selectEntry)) { note in
            guard let id = note.object as? Int64 else { return }
            selected = (try? env.entries.entry(id: id)) ?? nil
            showDashboard = false
        }
        .onReceive(NotificationCenter.default.publisher(for: WindowManager.dataDidChange)) { _ in
            model.load()
            // Clear only if the selected entry truly no longer exists — not merely
            // because the current filter excludes it (an externally focused entry
            // may sit outside the active filter).
            if let sel = selected, let sid = sel.id,
               ((try? env.entries.entry(id: sid)) ?? nil) == nil {
                selected = nil
            }
        }
        .confirmationDialog(
            L.t("Delete \u{201C}\(pendingDelete?.rawText ?? "")\u{201D}?",
                "Xóa \u{201C}\(pendingDelete?.rawText ?? "")\u{201D}?"),
            isPresented: Binding(get: { pendingDelete != nil }, set: { if !$0 { pendingDelete = nil } }),
            titleVisibility: .visible
        ) {
            Button(L.t("Delete", "Xóa"), role: .destructive) {
                if let id = pendingDelete?.id {
                    try? env.entries.delete(id: id)
                    if selected?.id == id { selected = nil }
                    WindowManager.notifyDataChanged()
                }
                pendingDelete = nil
            }
            Button(L.t("Cancel", "Hủy"), role: .cancel) { pendingDelete = nil }
        } message: {
            Text(L.t("This can't be undone.", "Không thể hoàn tác."))
        }
    }

    // MARK: Detail pane

    @ViewBuilder private var detailPane: some View {
        if let entry = selected {
            VStack(spacing: 0) {
                HStack {
                    Spacer()
                    Button(role: .destructive) { pendingDelete = entry } label: { Image(systemName: "trash") }
                        .buttonStyle(.plain).foregroundStyle(Theme.textDanger)
                        .accessibilityLabel(L.t("Delete", "Xóa"))
                }
                .padding(8).background(Theme.bgSecondary)
                Hairline()
                Group {
                    switch entry.cardType {
                    case .word:          WordDetailView(entry: entry).id(entry.id)
                    case .phrase:        PhraseDetailView(entry: entry).id(entry.id)
                    case .paragraphItem: ParagraphItemDetailView(entry: entry).id(entry.id)
                    case .none:          Text("Unknown entry").padding()
                    }
                }
            }
        } else {
            ContentUnavailableView {
                Label(L.t("Select a word", "Chọn một từ"), systemImage: "character.book.closed")
            } description: {
                Text(L.t("Choose an entry from the list to see its details.",
                         "Chọn một từ trong danh sách để xem chi tiết."))
            }
        }
    }

    // MARK: Sidebar

    // Sidebar order follows mockup #4: nav → Category → Level → Language, with a
    // statcard pinned to the bottom (outside the scroll, mockup `margin-top:auto`).
    private var sidebar: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 2) {
                    dashboardNavItem()
                    navItem(L.t("Due today", "Đến hạn hôm nay"), system: "rectangle.stack", count: model.dueCount, filter: .due)
                    navItem(L.t("All words", "Tất cả"), system: "books.vertical", count: model.total, filter: .all)
                    navItem(L.t("This week", "Tuần này"), system: "clock", count: model.weekCount, filter: .week)

                    categorySection
                    typeSection
                    levelSection
                    languageSection
                }
                .padding(.horizontal, 8).padding(.vertical, 10)
            }
            statcard
        }
        .background(Theme.bgSecondary)
    }

    @ViewBuilder private var categorySection: some View {
        if !model.categories.isEmpty || model.uncategorizedCount > 0 {
            sidebarLabel(L.t("Category", "Chủ đề"))
            // Top categories by count; the rest collapse behind "+N more" (mockup #4).
            let ordered = model.categories.sorted {
                (model.categoryCounts[$0] ?? 0, $1) > (model.categoryCounts[$1] ?? 0, $0)
            }
            let shown = showAllCategories ? ordered : Array(ordered.prefix(Self.categoryCap))
            ForEach(shown, id: \.self) { name in
                categoryItem(name, count: model.categoryCounts[name] ?? 0, filter: .category(name))
            }
            if !showAllCategories && ordered.count > Self.categoryCap {
                Button { showAllCategories = true } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "ellipsis").font(.system(size: 12)).frame(width: 9)
                        Text(L.t("+\(ordered.count - Self.categoryCap) more", "+\(ordered.count - Self.categoryCap) nữa"))
                            .font(.system(size: 13))
                        Spacer()
                    }
                    .padding(.horizontal, 10).padding(.vertical, 6)
                    .foregroundStyle(Theme.textTertiary)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
            if model.uncategorizedCount > 0 {
                categoryItem(L.t("Uncategorized", "Chưa phân loại"),
                             count: model.uncategorizedCount, filter: .uncategorized, colorIndex: nil)
            }
        }
    }

    @ViewBuilder private var typeSection: some View {
        if model.types.count > 1 {
            sidebarLabel(L.t("Type", "Loại"))
            ForEach(model.types, id: \.self) { t in
                navItem(LibraryViewModel.typeLabel(t), system: typeIcon(t),
                        count: model.count(forType: t), filter: .type(t))
            }
        }
    }

    private func typeIcon(_ raw: String) -> String {
        switch CardType(rawValue: raw) {
        case .word: return "textformat"
        case .phrase: return "text.quote"
        case .paragraphItem: return "text.alignleft"
        case .none: return "doc.text"
        }
    }

    @ViewBuilder private var levelSection: some View {
        if !model.cefrLevels.isEmpty {
            sidebarLabel(L.t("Level", "Cấp độ"))
            // Horizontal wrapping chips (mockup `.lvl-row`): "A1 8", "A2 18", …
            FlowLayout(spacing: 5) {
                ForEach(model.cefrLevels, id: \.self) { level in
                    levelChip(level, count: model.count(forCEFR: level))
                }
            }
            .padding(.horizontal, 9).padding(.top, 2)
        }
    }

    @ViewBuilder private var languageSection: some View {
        if model.languages.count > 1 {
            sidebarLabel(L.t("Language", "Ngôn ngữ"))
            ForEach(model.languages, id: \.self) { lang in
                navItem(lang.uppercased(), system: "flag", count: model.count(forLanguage: lang),
                        filter: .language(lang))
            }
        }
    }

    private func levelChip(_ level: String, count: Int) -> some View {
        let on = !showDashboard && model.filter == .cefr(level)
        return Button { select(on ? .all : .cefr(level)) } label: {
            HStack(spacing: 4) {
                Text(level.uppercased()).font(.system(size: 11, weight: .medium))
                Text("\(count)").font(.system(size: 10)).foregroundStyle(on ? Theme.accent : Theme.textTertiary)
            }
            .padding(.horizontal, 7).padding(.vertical, 3)
            .foregroundStyle(on ? Theme.accentText : Theme.textSecondary)
            .background(on ? Theme.accentBg : Theme.bgTertiary, in: Capsule())
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
    }

    /// Colour for the local "requests today" count: muted normally, amber as it
    /// nears the warn threshold, red once at/over it (surfaces the warn state).
    /// Reads the limit live from env.settings so a Settings change applies instantly.
    private var warnCountColor: Color {
        let limit = max(1, env.settings.dailyLimit)
        if model.quotaUsed >= limit { return .red }
        if Double(model.quotaUsed) / Double(limit) >= 0.8 { return .orange }
        return Theme.textSecondary
    }

    /// Localized tooltip for the reload control; shows the cooldown when active.
    private var reloadHelp: String {
        if let s = model.quotaCooldownRetry {
            return L.t("Just updated · retry in \(s)s", "Vừa cập nhật · thử lại sau \(s)s")
        }
        return L.t("Reload quota", "Tải lại hạn mức")
    }

    /// Bottom statcard (mockup #4): streak, real Antigravity quota (click-to-reload), on-disk size.
    private var statcard: some View {
        let gKey = AntigravityModelGroup.groupKey(forModel: env.settings.model)
        let group: AntigravityQuotaSummary.Group? = model.antigravityQuota.flatMap { q in
            q.groups.first { $0.key == gKey } ?? (gKey == nil ? q.groups.first { $0.key == q.bindingGroupKey } : nil)
        }
        return VStack(alignment: .leading, spacing: 6) {
            statRow(nil, system: "flame", label: L.t("Streak", "Chuỗi"),
                    value: L.t("\(model.streak) days", "\(model.streak) ngày"))
            statRow(nil, system: "internaldrive", label: L.t("Disk", "Ổ đĩa"), value: model.diskLabel)

            // Quota header (label + reload) — sits OUTSIDE the tinted panel.
            Button {
                model.reloadQuota()
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: "bolt").font(.system(size: 10))
                    Text(L.t("Quota", "Hạn mức")).font(.system(size: 11))
                    Spacer()
                    if showCooldownNote, let s = model.quotaCooldownRetry {
                        Text("\(s)s").font(.system(size: 9)).foregroundStyle(Theme.textTertiary)
                            .transition(.opacity)
                    }
                    if model.quotaReloading {
                        ProgressView().controlSize(.mini)
                    } else {
                        Image(systemName: "arrow.clockwise").font(.system(size: 9))
                            .foregroundStyle(Theme.textTertiary)
                            .scaleEffect(reloadPulse ? 1.35 : 1)
                            .opacity(reloadPulse ? 0.4 : 1)
                    }
                }
                .foregroundStyle(Theme.textSecondary)
                .contentShape(Rectangle())
                .help(reloadHelp)
            }
            .buttonStyle(.plain)
            .disabled(model.quotaReloading)
            .onChange(of: model.quotaCooldownRetry) { _, newValue in
                guard newValue != nil else { return }
                withAnimation(.easeInOut(duration: 0.12)) { reloadPulse = true }
                withAnimation { showCooldownNote = true }
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.18) {
                    withAnimation(.easeInOut(duration: 0.2)) { reloadPulse = false }
                }
                DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
                    withAnimation { showCooldownNote = false }
                }
            }
            .padding(.top, 2)

            // Tinted panel: real Antigravity quota bars + the local daily limit.
            VStack(alignment: .leading, spacing: 7) {
                if let grp = group {
                    quotaBucketRow(grp.fiveHour, label: L.t("5-hour", "5 giờ"))
                    quotaBucketRow(grp.weekly, label: L.t("Weekly", "Hàng tuần"))
                } else {
                    Text(L.t("Open Antigravity to see quota", "Mở Antigravity để xem quota"))
                        .font(.system(size: 10)).foregroundStyle(Theme.textTertiary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Rectangle().fill(Theme.borderTertiary)
                    .frame(height: Theme.hairline).opacity(0.7)
                HStack(spacing: 5) {
                    Image(systemName: "calendar").font(.system(size: 10))
                        .foregroundStyle(Theme.textTertiary)
                    Text(L.t("Daily limit", "Hạn mức ngày"))
                        .font(.system(size: 10)).foregroundStyle(Theme.textTertiary)
                    Spacer(minLength: 4)
                    DailyLimitRing(used: model.quotaUsed, limit: env.settings.dailyLimit, color: warnCountColor)
                }
            }
            .padding(8)
            .background(Theme.bgSecondary, in: RoundedRectangle(cornerRadius: Theme.radiusMd))
        }
        .padding(9)
        .background(Theme.bgPrimary, in: RoundedRectangle(cornerRadius: Theme.radiusLg))
        .overlay(RoundedRectangle(cornerRadius: Theme.radiusLg).strokeBorder(Theme.borderTertiary, lineWidth: Theme.hairline))
        .padding(8)
        .task { model.loadQuota() }
    }

    @ViewBuilder
    private func quotaBucketRow(_ bucket: AntigravityQuotaSummary.Bucket?, label: String) -> some View {
        if let bucket {
            let remaining = bucket.remainingFraction ?? 0
            let severity = QuotaSeverity.forRemaining(bucket.remainingFraction)
            let barColor: Color = {
                switch severity {
                case .ok: return Theme.accent
                case .amber: return .orange
                case .red: return .red
                }
            }()
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 5) {
                    Text(label)
                        .font(.system(size: 10)).foregroundStyle(Theme.textSecondary)
                        .lineLimit(1)
                    Spacer(minLength: 4)
                    Text("\(Int(remaining * 100))%")
                        .font(.system(size: 10, weight: .medium)).foregroundStyle(Theme.textPrimary)
                }
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Capsule().fill(Theme.borderTertiary).frame(height: 3)
                        Capsule().fill(barColor)
                            .frame(width: geo.size.width * max(0, min(1, remaining)), height: 3)
                    }
                }
                .frame(height: 3)
            }
        }
    }

    @ViewBuilder private func statRow(_ text: String?, system: String? = nil,
                                      label: String = "", value: String) -> some View {
        HStack(spacing: 5) {
            if let system { Image(systemName: system).font(.system(size: 10)); Text(label) }
            if let text { Text(text) }
            Spacer()
            Text(value).font(.system(size: 11, weight: .medium)).foregroundStyle(Theme.textPrimary)
        }
        .font(.system(size: 11)).foregroundStyle(Theme.textSecondary)
    }

    private func sidebarLabel(_ text: String) -> some View {
        SecLabel(text).padding(.leading, 10).padding(.top, 14).padding(.bottom, 6)
    }

    /// Switching to a filter always leaves the dashboard view.
    private func select(_ f: LibraryFilter) {
        model.filter = f
        showDashboard = false
    }

    /// Dashboard sidebar row — first item, mirrors navItem's selected styling but
    /// has no count and is driven by `showDashboard` instead of a filter match.
    private func dashboardNavItem() -> some View {
        let on = showDashboard
        return Button { showDashboard = true } label: {
            HStack(spacing: 9) {
                Image(systemName: "house").font(.system(size: 13)).frame(width: 16)
                Text(L.t("Home", "Trang chủ")).font(.system(size: 13, weight: on ? .medium : .regular))
                Spacer()
            }
            .padding(.horizontal, 10).padding(.vertical, 6)
            .foregroundStyle(on ? Theme.accentText : Theme.textSecondary)
            .background(on ? Theme.accentBg : .clear, in: RoundedRectangle(cornerRadius: Theme.radiusMd))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func navItem(_ title: String, system: String, count: Int, filter: LibraryFilter) -> some View {
        let on = !showDashboard && model.filter == filter
        return Button { select(filter) } label: {
            HStack(spacing: 9) {
                Image(systemName: system).font(.system(size: 13)).frame(width: 16)
                Text(title).font(.system(size: 13, weight: on ? .medium : .regular))
                Spacer()
                Text("\(count)").font(.system(size: 11))
                    .foregroundStyle(on ? Theme.accent : Theme.textTertiary)
            }
            .padding(.horizontal, 10).padding(.vertical, 6)
            .foregroundStyle(on ? Theme.accentText : Theme.textSecondary)
            .background(on ? Theme.accentBg : .clear, in: RoundedRectangle(cornerRadius: Theme.radiusMd))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    /// Sidebar row for a category: square color dot + name + count. `colorIndex`
    /// uses the sentinel `-1` to mean "look up the stored index by title"; pass
    /// `nil` explicitly for the colorless Uncategorized group.
    private func categoryItem(_ title: String, count: Int, filter: LibraryFilter,
                              colorIndex: Int? = -1) -> some View {
        let on = !showDashboard && model.filter == filter
        let idx = (colorIndex == -1) ? model.categoryColorIndex[title] : colorIndex
        return Button { select(filter) } label: {
            HStack(spacing: 8) {
                RoundedRectangle(cornerRadius: 2)
                    .fill(idx.map { Theme.categoryColor($0) } ?? Theme.textTertiary)
                    .frame(width: 7, height: 7)
                Text(title).font(.system(size: 13, weight: on ? .medium : .regular)).lineLimit(1)
                Spacer()
                Text("\(count)").font(.system(size: 11))
                    .foregroundStyle(on ? Theme.accent : Theme.textTertiary)
            }
            .padding(.horizontal, 10).padding(.vertical, 6)
            .foregroundStyle(on ? Theme.accentText : Theme.textSecondary)
            .background(on ? Theme.accentBg : .clear, in: RoundedRectangle(cornerRadius: Theme.radiusMd))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    // MARK: Main

    private var main: some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                MetricCard(value: "\(model.dueCount)", label: L.t("Due today", "Đến hạn"), accent: dueAccent)
                MetricCard(value: "\(model.total)", label: L.t("Total", "Tổng"), accent: Theme.textTertiary)
                MetricCard(value: "\(model.reviewedCount)", label: L.t("Reviewed", "Đã ôn"), accent: Theme.accent)
                MetricCard(value: "\(model.weekCount)", label: L.t("This week", "Tuần này"), accent: Color(hex: 0x1D9E75))
            }
            .padding(.horizontal, 16).padding(.vertical, 12)

            CaptureFormView()
                .padding(.horizontal, 16).padding(.bottom, 4)

            HStack {
                SecLabel("\(model.filterTitle) · \(visibleRows.count)")
                Spacer()
                if model.dueCount > 0 {
                    Button(L.t("Start review →", "Bắt đầu ôn →")) { WindowManager.shared.showReview() }
                        .buttonStyle(.plain)
                        .font(.system(size: 12)).foregroundStyle(Theme.accent)
                }
            }
            .padding(.horizontal, 16).padding(.bottom, 8).padding(.top, 4)

            list
        }
        .background(Theme.bgPrimary)
        .searchable(text: $search, placement: .toolbar, prompt: L.t("Search words…", "Tìm từ…"))
        .toolbar {
            ToolbarItem {
                Menu {
                    ForEach(ExportFormat.allCases) { format in
                        Button(L.t("Export as \(format.rawValue)", "Xuất \(format.rawValue)")) {
                            Exporter.presentSavePanel(model.rows.map(\.entry), format: format,
                                                      meaningLanguage: env.settings.meaningLanguage)
                        }
                    }
                } label: { Label(L.t("Export", "Xuất"), systemImage: "square.and.arrow.up") }
                .disabled(model.rows.isEmpty)
            }
        }
    }

    private var visibleRows: [LibraryRow] {
        let rows = model.rows
        guard !search.isEmpty else { return rows }
        let q = search.lowercased()
        return rows.filter { $0.entry.rawText.lowercased().contains(q) }
    }

    private var list: some View {
        ScrollView {
            // Dual-role search: a query that matches nothing offers to capture it.
            if !search.isEmpty && visibleRows.isEmpty {
                Button {
                    CaptureController.shared.capture(search, source: SourceContext(appName: "Manual entry"))
                    search = ""
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "return")
                        Text(L.t("Capture “\(search)” as new", "Lưu “\(search)” như từ mới"))
                    }
                    .font(.system(size: 12, weight: .medium)).foregroundStyle(Theme.accent)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 16).padding(.vertical, 10)
                }
                .buttonStyle(.plain)
                Hairline()
            }
            LazyVStack(spacing: 0) {
                ForEach(visibleRows) { row in
                    Button { selected = row.entry } label: {
                        LibraryRowView(row: row)
                    }
                    .buttonStyle(.plain)
                    .contextMenu {
                        Button(role: .destructive) { pendingDelete = row.entry } label: {
                            Label(L.t("Delete", "Xóa"), systemImage: "trash")
                        }
                    }
                    Hairline()
                }
            }
            if visibleRows.isEmpty && search.isEmpty {
                ContentUnavailableView(L.t("No words", "Chưa có từ"), systemImage: "tray",
                                       description: Text(L.t("Capture a word from the menubar to get started.",
                                                             "Bắt một từ từ menubar để bắt đầu.")))
                    .padding(.top, 40)
            }
        }
    }
}

/// One Library row: due dot, word, meaning, CEFR pill, interval.
struct LibraryRowView: View {
    @EnvironmentObject private var env: AppEnvironment
    let row: LibraryRow

    var body: some View {
        HStack(spacing: 10) {
            DueDot(status: row.dueStatus)
            Text(row.entry.rawText)
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(Theme.textPrimary)
                .frame(width: 130, alignment: .leading)
                .lineLimit(1)
            analysisStateContent
        }
        .padding(.horizontal, 16).padding(.vertical, 10)
        .contentShape(Rectangle())
    }

    @ViewBuilder private var analysisStateContent: some View {
        switch row.entry.analysisState {
        case AnalysisState.analyzing.rawValue:
            Text("Analyzing…")
                .font(.system(size: 12)).foregroundStyle(Theme.textTertiary)
                .frame(maxWidth: .infinity, alignment: .leading).lineLimit(1)
                .skeleton()
        case AnalysisState.failed.rawValue:
            Text(L.t("Analysis failed", "Phân tích thất bại"))
                .font(.system(size: 12)).foregroundStyle(Theme.textTertiary)
                .frame(maxWidth: .infinity, alignment: .leading).lineLimit(1)
            Button(L.t("Retry", "Thử lại")) {
                guard let id = row.entry.id else { return }
                env.retryAnalysis(id: id)
            }
            .buttonStyle(.plain)
            .font(.system(size: 11)).foregroundStyle(Theme.accent)
        default:
            Text(row.meaning ?? "")
                .font(.system(size: 12)).foregroundStyle(Theme.textSecondary)
                .frame(maxWidth: .infinity, alignment: .leading).lineLimit(1)
            if let cefr = row.cefr { Pill.cefr(cefr) }
            Text(row.intervalLabel)
                .font(.system(size: 11)).foregroundStyle(Theme.textTertiary)
                .frame(width: 64, alignment: .trailing)
        }
    }
}
// Detail is shown inline in LibraryView's detail pane (master-detail), not a sheet.
