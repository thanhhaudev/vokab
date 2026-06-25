import SwiftUI
import VokabKit

/// Settings → AI Engine tab (SPEC §12 surface #9, §13). Only AI Engine is
/// designed; other tabs are placeholders per the SPEC. No API-key field — auth
/// is managed by `agy login`.
struct SettingsView: View {
    @Environment(\.displayScale) private var displayScale
    @EnvironmentObject var env: AppEnvironment
    @State private var tab: SettingsTab = .aiEngine
    @State private var settings = VokabSettings()
    @State private var models: [String] = []
    @State private var testResult: TestState = .none
    @State private var usedToday = 0
    @State private var modelsLoading = false
    @State private var langTick = 0   // forces re-render when app language changes
    @State private var launchAtLogin = false
    @State private var recordingHotkey = false
    @State private var hotkeyMonitor: Any?

    enum SettingsTab: String, CaseIterable { case general, aiEngine, capture, review, export
        var title: String {
            switch self { case .general: return L.t("General", "Chung"); case .aiEngine: return "AI Engine"
            case .capture: return L.t("Capture", "Capture"); case .review: return L.t("Review", "Ôn tập")
            case .export: return L.t("Export", "Xuất") }
        }
        var icon: String {
            switch self { case .general: return "gearshape"; case .aiEngine: return "cpu"
            case .capture: return "cursorarrow.click"; case .review: return "rectangle.stack"
            case .export: return "square.and.arrow.up" }
        }
    }
    enum TestState: Equatable { case none, testing, ok, fail(String) }

    var body: some View {
        VStack(spacing: 0) {
            tabBar
            ScrollView {
                Group {
                    switch tab {
                    case .aiEngine: aiEngine
                    case .general:  general
                    case .review:   review
                    case .capture:  capture
                    case .export:   export
                    }
                }
                .padding(16)
            }
        }
        .frame(width: 480, height: 580)
        .background(Theme.bgPrimary)
        .id(langTick)
        .onAppear {
            settings = env.settings
            usedToday = (try? env.quota.count(on: Date())) ?? 0
            launchAtLogin = LoginItem.isEnabled
            models = ModelCache.load()          // instant from cache
            let path = settings.agyPath
            modelsLoading = models.isEmpty
            Task {
                let fresh = await AgyTooling.listModelsAsync(agyPath: path)
                modelsLoading = false
                if !fresh.isEmpty { models = fresh; ModelCache.save(fresh) }
            }
        }
    }

    // MARK: General

    private var general: some View {
        VStack(alignment: .leading, spacing: 16) {
            group(L.t("Appearance", "Giao diện")) {
                SettingsRow(L.t("Theme", "Chủ đề"),
                            sub: L.t("System follows macOS", "Hệ thống theo macOS")) {
                    Picker("", selection: Binding(
                        get: { settings.appearanceMode },
                        set: { settings.appearanceMode = $0; persist(); AppearanceController.apply($0) }
                    )) {
                        Text(L.t("System", "Hệ thống")).tag(AppearanceMode.system)
                        Text(L.t("Light", "Sáng")).tag(AppearanceMode.light)
                        Text(L.t("Dark", "Tối")).tag(AppearanceMode.dark)
                    }
                    .pickerStyle(.segmented).labelsHidden().fixedSize()
                }
            }
            group(L.t("Startup", "Khởi động")) {
                SettingsRow(L.t("Launch at login", "Mở khi đăng nhập")) {
                    Toggle("", isOn: Binding(
                        get: { launchAtLogin },
                        set: { launchAtLogin = $0; LoginItem.set($0); launchAtLogin = LoginItem.isEnabled }
                    )).labelsHidden()
                }
            }
            group(L.t("Toast", "Toast")) {
                SettingsRow(L.t("Position", "Vị trí")) {
                    Menu {
                        ForEach(ToastCorner.allCases, id: \.self) { c in
                            Button(cornerLabel(c)) {
                                settings.toastPosition = c; ToastCenter.shared.corner = c; persist()
                            }
                        }
                    } label: { selLabel(cornerLabel(settings.toastPosition)) }
                        .menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize()
                }
            }
            group(L.t("Global hotkey", "Phím tắt toàn cục")) {
                SettingsRow(L.t("Enable", "Bật"),
                            sub: L.t("Opens quick capture from anywhere", "Mở capture nhanh từ bất kỳ đâu")) {
                    Toggle("", isOn: Binding(
                        get: { settings.globalHotkeyEnabled },
                        set: { settings.globalHotkeyEnabled = $0; persist(); applyHotkey()
                               // Ask for Accessibility here (deliberate, Settings focused) so the
                               // hotkey can auto-grab the selection without a manual ⌘C.
                               if $0 { SelectionGrabber.requestAccessibility() } }
                    )).labelsHidden()
                }
                SettingsRow(L.t("Shortcut", "Tổ hợp")) {
                    miniButton(recordingHotkey
                               ? L.t("Press keys…", "Nhấn phím…")
                               : GlobalHotkey.label(keyCode: settings.globalHotkeyKeyCode, modifiers: settings.globalHotkeyModifiers)) {
                        recordingHotkey ? stopRecording() : startRecording()
                    }
                    .disabled(!settings.globalHotkeyEnabled)
                }
            }
            group(L.t("Pronunciation", "Phát âm")) {
                SettingsRow(L.t("Accent", "Giọng")) {
                    Picker("", selection: Binding(
                        get: { Accent(settingsValue: settings.pronunciationAccent) },
                        set: { settings.pronunciationAccent = $0.bcp47; persist() }
                    )) {
                        Text(L.t("US", "Mỹ")).tag(Accent.us)
                        Text(L.t("UK", "Anh")).tag(Accent.uk)
                    }
                    .pickerStyle(.segmented).labelsHidden().fixedSize()
                }
                SettingsRow(L.t("Auto-play on flip", "Tự đọc khi lật thẻ"),
                            sub: L.t("Speak the word when a card is revealed",
                                     "Đọc từ khi lật lộ đáp án")) {
                    Toggle("", isOn: Binding(
                        get: { settings.autoPlayPronunciation },
                        set: { settings.autoPlayPronunciation = $0; persist() }
                    )).labelsHidden()
                }
            }
        }
    }

    private func applyHotkey() {
        if settings.globalHotkeyEnabled {
            GlobalHotkey.shared.register(keyCode: settings.globalHotkeyKeyCode, modifiers: settings.globalHotkeyModifiers)
        } else {
            GlobalHotkey.shared.unregister()
        }
    }

    private func startRecording() {
        recordingHotkey = true
        hotkeyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            let mods = Int(event.modifierFlags.intersection(.deviceIndependentFlagsMask).rawValue)
            settings.globalHotkeyKeyCode = Int(event.keyCode)
            settings.globalHotkeyModifiers = mods
            persist(); applyHotkey(); stopRecording()
            return nil   // swallow the event
        }
    }

    private func stopRecording() {
        if let m = hotkeyMonitor { NSEvent.removeMonitor(m); hotkeyMonitor = nil }
        recordingHotkey = false
    }

    private func cornerLabel(_ c: ToastCorner) -> String {
        switch c {
        case .topTrailing: return L.t("Top right", "Trên phải")
        case .topLeading: return L.t("Top left", "Trên trái")
        case .bottomTrailing: return L.t("Bottom right", "Dưới phải")
        case .bottomLeading: return L.t("Bottom left", "Dưới trái")
        }
    }

    // MARK: Review

    private var review: some View {
        VStack(alignment: .leading, spacing: 16) {
            group(L.t("Production card", "Thẻ luyện viết")) {
                SettingsRow(L.t("Unlock after (days)", "Mở sau (ngày)"),
                            sub: L.t("Interval before writing practice", "Khoảng cách trước khi luyện viết")) {
                    stepperField("\(settings.productionUnlockInterval)",
                                 dec: { settings.productionUnlockInterval = max(1, settings.productionUnlockInterval - 1); persist() },
                                 inc: { settings.productionUnlockInterval = min(60, settings.productionUnlockInterval + 1); persist() })
                }
                SettingsRow(L.t("Min correct reviews", "Số lần đúng tối thiểu")) {
                    stepperField("\(settings.productionUnlockReps)",
                                 dec: { settings.productionUnlockReps = max(0, settings.productionUnlockReps - 1); persist() },
                                 inc: { settings.productionUnlockReps = min(20, settings.productionUnlockReps + 1); persist() })
                }
            }
            group(L.t("Cloze card", "Thẻ điền từ")) {
                SettingsRow(L.t("Unlock after (days)", "Mở sau (ngày)"),
                            sub: L.t("Interval before fill-in-the-blank", "Khoảng cách trước khi điền từ")) {
                    stepperField("\(settings.clozeUnlockInterval)",
                                 dec: { settings.clozeUnlockInterval = max(1, settings.clozeUnlockInterval - 1); persist() },
                                 inc: { settings.clozeUnlockInterval = min(60, settings.clozeUnlockInterval + 1); persist() })
                }
                SettingsRow(L.t("Min correct reviews", "Số lần đúng tối thiểu")) {
                    stepperField("\(settings.clozeUnlockReps)",
                                 dec: { settings.clozeUnlockReps = max(0, settings.clozeUnlockReps - 1); persist() },
                                 inc: { settings.clozeUnlockReps = min(20, settings.clozeUnlockReps + 1); persist() })
                }
            }
            group(L.t("Error card", "Thẻ sửa lỗi")) {
                SettingsRow(L.t("Unlock after (days)", "Mở sau (ngày)"),
                            sub: L.t("Interval before error practice (phrases)", "Khoảng cách trước khi luyện lỗi (cụm từ)")) {
                    stepperField("\(settings.errorUnlockInterval)",
                                 dec: { settings.errorUnlockInterval = max(1, settings.errorUnlockInterval - 1); persist() },
                                 inc: { settings.errorUnlockInterval = min(60, settings.errorUnlockInterval + 1); persist() })
                }
                SettingsRow(L.t("Min correct reviews", "Số lần đúng tối thiểu")) {
                    stepperField("\(settings.errorUnlockReps)",
                                 dec: { settings.errorUnlockReps = max(0, settings.errorUnlockReps - 1); persist() },
                                 inc: { settings.errorUnlockReps = min(20, settings.errorUnlockReps + 1); persist() })
                }
            }
            group(L.t("Advanced", "Nâng cao")) {
                SettingsRow(L.t("Starting ease", "Ease khởi điểm"),
                            sub: L.t("SM-2 ease for new cards", "Ease SM-2 cho thẻ mới")) {
                    stepperField(String(format: "%.1f", settings.startingEase),
                                 dec: { settings.startingEase = max(1.3, (settings.startingEase - 0.1)); persist() },
                                 inc: { settings.startingEase = min(3.5, (settings.startingEase + 0.1)); persist() })
                }
            }
        }
    }

    // MARK: Capture

    private var capture: some View {
        VStack(alignment: .leading, spacing: 16) {
            group(L.t("Language", "Ngôn ngữ")) {
                SettingsRow(L.t("Auto-detect language", "Tự nhận diện ngôn ngữ"),
                            sub: L.t("Detect the source language on capture", "Nhận diện ngôn ngữ nguồn khi capture")) {
                    Toggle("", isOn: Binding(
                        get: { settings.autoDetectLanguage },
                        set: { settings.autoDetectLanguage = $0; persist() }
                    )).labelsHidden()
                }
                SettingsRow(L.t("Default language", "Ngôn ngữ mặc định"),
                            sub: L.t("Used when auto-detect is off", "Dùng khi tắt tự nhận diện")) {
                    Menu {
                        Button("English") { settings.defaultCaptureLanguage = "en"; persist() }
                        Button("Tiếng Việt") { settings.defaultCaptureLanguage = "vi"; persist() }
                    } label: { selLabel(settings.defaultCaptureLanguage.uppercased()) }
                        .menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize()
                        .disabled(settings.autoDetectLanguage)
                }
            }
            group(L.t("Filter", "Lọc")) {
                SettingsRow(L.t("Min paragraph CEFR", "CEFR tối thiểu cho đoạn văn")) {
                    Menu {
                        ForEach(CEFR.allCases, id: \.self) { level in
                            Button(level.rawValue.uppercased()) { settings.minParagraphLevel = level; persist() }
                        }
                    } label: { selLabel(settings.minParagraphLevel.rawValue.uppercased()) }
                        .menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize()
                }
            }
        }
    }

    // MARK: Export

    private var export: some View {
        VStack(alignment: .leading, spacing: 16) {
            group(L.t("Export deck", "Xuất bộ thẻ")) {
                ForEach(ExportFormat.allCases) { format in
                    SettingsRow(format.rawValue) {
                        miniButton(L.t("Export…", "Xuất…")) {
                            Exporter.presentSavePanel((try? env.entries.all()) ?? [], format: format,
                                                      meaningLanguage: env.settings.meaningLanguage)
                        }
                    }
                }
            }
        }
    }

    private func stepperField(_ value: String, dec: @escaping () -> Void, inc: @escaping () -> Void) -> some View {
        HStack(spacing: 6) {
            fieldText(value)
            miniButton("−", action: dec)
            miniButton("+", action: inc)
        }
    }

    // MARK: Tab bar

    private var tabBar: some View {
        HStack(spacing: 2) {
            ForEach(SettingsTab.allCases, id: \.self) { t in
                Button { tab = t } label: {
                    VStack(spacing: 3) {
                        Image(systemName: t.icon).font(.system(size: 17))
                        Text(t.title).font(.system(size: 11))
                    }
                    .frame(minWidth: 62).padding(.horizontal, 12).padding(.vertical, 6)
                    .foregroundStyle(tab == t ? Theme.accentText : Theme.textSecondary)
                    .background(tab == t ? Theme.accentBg : .clear, in: RoundedRectangle(cornerRadius: Theme.radiusMd))
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
            Spacer()
        }
        .padding(.horizontal, 10).padding(.vertical, 8)
        .background(Theme.bgSecondary)
        .overlay(alignment: .bottom) { Hairline() }
    }

    // MARK: AI Engine

    private var aiEngine: some View {
        VStack(alignment: .leading, spacing: 16) {
            group("agy CLI") {
                SettingsRow(L.t("Binary path", "Đường dẫn binary")) {
                    HStack(spacing: 8) {
                        fieldText(settings.agyPath, mono: true)
                        miniButton(L.t("Test", "Kiểm tra")) { runTest() }
                    }
                }
                SettingsRow(L.t("Status", "Trạng thái"), sub: L.t("Auto-detected at launch", "Tự dò khi khởi động")) {
                    statusBadge
                }
                SettingsRow(L.t("Model / profile", "Model / profile")) {
                    modelPicker($settings.model)
                }
                SettingsRow(L.t("Enrich model", "Model enrich"),
                            sub: L.t("Used for detail enrichment", "Dùng cho enrich chi tiết")) {
                    modelPicker($settings.enrichModel)
                }
                SettingsRow(L.t("Authentication", "Xác thực"), sub: L.t("Managed by agy login", "Quản lý bởi agy login")) {
                    badge(L.t("Signed in", "Đã đăng nhập"), system: "person.crop.circle.badge.checkmark",
                          fg: Theme.infoFg, bg: Theme.infoBg)
                }
            }

            group(L.t("Language", "Ngôn ngữ")) {
                SettingsRow(L.t("App language", "Ngôn ngữ ứng dụng"),
                            sub: L.t("Relaunch to apply everywhere", "Khởi động lại để áp dụng toàn bộ")) {
                    Menu {
                        Button("English") { setAppLanguage("en") }
                        Button("Tiếng Việt") { setAppLanguage("vi") }
                    } label: { selLabel(settings.appLanguage == "vi" ? "Tiếng Việt" : "English") }
                        .menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize()
                }
                SettingsRow(L.t("Meaning language", "Ngôn ngữ giải nghĩa"),
                            sub: L.t("Language of definitions returned by agy", "Ngôn ngữ phần giải nghĩa agy trả về")) {
                    Menu {
                        ForEach(Self.meaningLanguageCodes, id: \.self) { code in
                            Button(languageLabel(code)) { settings.meaningLanguage = code; persist() }
                        }
                    } label: { selLabel(languageLabel(settings.meaningLanguage)) }
                        .menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize()
                }
            }

            group(L.t("Quota & usage", "Quota & sử dụng")) {
                SettingsRow(L.t("Warn threshold (req/day)", "Ngưỡng cảnh báo (request/ngày)"),
                            sub: L.t("Max agy calls per day", "Số lần gọi agy tối đa / ngày")) {
                    HStack(spacing: 6) {
                        fieldText("\(settings.dailyLimit)")
                        miniButton("−") { settings.dailyLimit = max(10, settings.dailyLimit - 10); persist() }
                        miniButton("+") { settings.dailyLimit = min(2000, settings.dailyLimit + 10); persist() }
                    }
                }
                SettingsRow(L.t("Today", "Hôm nay"),
                            sub: L.t("Resets 00:00 · \(max(0, settings.dailyLimit - usedToday)) left",
                                     "Reset 00:00 · còn \(max(0, settings.dailyLimit - usedToday)) lượt")) {
                    HStack(spacing: 8) {
                        meter(Double(usedToday) / Double(max(settings.dailyLimit, 1)))
                        Text("\(usedToday) / \(settings.dailyLimit)").font(.system(size: 12)).foregroundStyle(Theme.textSecondary)
                    }
                }
                SettingsRow(L.t("Block capture when over threshold", "Chặn capture khi vượt ngưỡng")) {
                    Toggle("", isOn: Binding(
                        get: { settings.hardBlockOnLimit },
                        set: { settings.hardBlockOnLimit = $0; persist() }
                    )).labelsHidden()
                }
                SettingsRow(L.t("When limit reached", "Khi chạm giới hạn")) {
                    Menu {
                        Button(L.t("Pause capture", "Tạm dừng capture")) { settings.quotaHitBehavior = .pause; persist() }
                        Button(L.t("Queue", "Xếp hàng (queue)")) { settings.quotaHitBehavior = .queue; persist() }
                        Button(L.t("Skip", "Bỏ qua")) { settings.quotaHitBehavior = .skip; persist() }
                    } label: { selLabel(quotaLabel) }.menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize()
                }
            }

            group(L.t("Performance", "Hiệu năng")) {
                SettingsRow(L.t("Timeout per request", "Timeout mỗi request")) {
                    HStack(spacing: 6) {
                        fieldText("\(settings.timeoutSeconds)s")
                        miniButton("−") { settings.timeoutSeconds = max(5, settings.timeoutSeconds - 5); persist() }
                        miniButton("+") { settings.timeoutSeconds = min(120, settings.timeoutSeconds + 5); persist() }
                    }
                }
                SettingsRow(L.t("Max concurrent captures", "Capture song song tối đa")) {
                    HStack(spacing: 6) {
                        fieldText("\(settings.maxConcurrent)")
                        miniButton("−") { settings.maxConcurrent = max(1, settings.maxConcurrent - 1); persist() }
                        miniButton("+") { settings.maxConcurrent = min(8, settings.maxConcurrent + 1); persist() }
                    }
                }
            }

            group(L.t("Advanced", "Nâng cao")) {
                SettingsRow(L.t("On agy JSON error", "Khi agy trả JSON lỗi")) {
                    Menu {
                        Button(L.t("Retry once", "Thử lại 1 lần")) { settings.jsonErrorBehavior = .retryOnce; persist() }
                        Button(L.t("Ask agy again", "Hỏi agy lại")) { settings.jsonErrorBehavior = .askAgain; persist() }
                        Button(L.t("Show raw", "Hiện raw")) { settings.jsonErrorBehavior = .showRaw; persist() }
                    } label: { selLabel(jsonErrorLabel) }.menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize()
                }
                SettingsRow(L.t("Min paragraph CEFR", "CEFR tối thiểu cho đoạn văn")) {
                    Menu {
                        ForEach(CEFR.allCases, id: \.self) { level in
                            Button(level.rawValue.uppercased()) { settings.minParagraphLevel = level; persist() }
                        }
                    } label: { selLabel(settings.minParagraphLevel.rawValue.uppercased()) }
                        .menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize()
                }
            }
        }
    }

    // MARK: Group + control chrome

    private func group<C: View>(_ title: String, @ViewBuilder content: () -> C) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            SecLabel(title)
            VStack(spacing: 0) { content() }
                // Each SettingsRow draws a full-width top hairline as its row
                // separator. Inside a bordered card the first row's hairline
                // overlaps the stroke border (darker top edge), so pull the
                // content up by one hairline to clip that first line away —
                // only the inter-row separators remain.
                .padding(.top, -Theme.hairline(displayScale))
                .background(Theme.bgSecondary)
                .clipShape(RoundedRectangle(cornerRadius: Theme.radiusMd))
                .overlay(RoundedRectangle(cornerRadius: Theme.radiusMd).strokeBorder(Theme.borderTertiary, lineWidth: Theme.hairline(displayScale)))
        }
    }

    private func fieldText(_ text: String, mono: Bool = false) -> some View {
        Text(text)
            .font(mono ? Theme.mono(12) : .system(size: 12)).foregroundStyle(Theme.textSecondary).lineLimit(1)
            .padding(.horizontal, 9).padding(.vertical, 4)
            .background(Theme.bgPrimary, in: RoundedRectangle(cornerRadius: 6))
            .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(Theme.borderSecondary, lineWidth: Theme.hairline(displayScale)))
    }

    private func miniButton(_ title: String, action: @escaping () -> Void) -> some View {
        Button(title, action: action).buttonStyle(.plain)
            .font(.system(size: 12)).foregroundStyle(Theme.textPrimary)
            .padding(.horizontal, 10).padding(.vertical, 4)
            .background(Theme.bgPrimary, in: RoundedRectangle(cornerRadius: 6))
            .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(Theme.borderSecondary, lineWidth: Theme.hairline(displayScale)))
    }

    /// A model dropdown driven by the live `agy models` list. Defaults to
    /// "agy default" (no fixed model); includes the current selection even if it
    /// isn't in the live list, so a saved/custom value is still reflected.
    private func modelPicker(_ selection: Binding<String?>) -> some View {
        let current = selection.wrappedValue
        var options = models
        if let c = current, !options.contains(c) { options.insert(c, at: 0) }
        return HStack(spacing: 6) {
            if modelsLoading && options.isEmpty {
                ProgressView().controlSize(.small)
            }
            Menu {
                Button(L.t("agy default", "agy mặc định")) { selection.wrappedValue = nil; persist() }
                if modelsLoading && options.isEmpty {
                    Text(L.t("Loading models…", "Đang tải models…"))
                }
                ForEach(options, id: \.self) { m in Button(m) { selection.wrappedValue = m; persist() } }
            } label: { selLabel(current ?? L.t("agy default", "agy mặc định")) }
                .menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize()
        }
    }

    private func selLabel(_ text: String) -> some View {
        HStack(spacing: 5) {
            Text(text).font(.system(size: 12)).foregroundStyle(Theme.textPrimary)
            Image(systemName: "chevron.down").font(.system(size: 10)).foregroundStyle(Theme.textTertiary)
        }
        .padding(.horizontal, 9).padding(.vertical, 4)
        .background(Theme.bgPrimary, in: RoundedRectangle(cornerRadius: 6))
        .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(Theme.borderSecondary, lineWidth: Theme.hairline(displayScale)))
    }

    private func badge(_ text: String, system: String, fg: Color, bg: Color) -> some View {
        Label(text, systemImage: system).font(.system(size: 11))
            .padding(.horizontal, 8).padding(.vertical, 2)
            .background(bg, in: Capsule()).foregroundStyle(fg)
    }

    private func meter(_ value: Double) -> some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(Theme.borderTertiary)
                Capsule().fill(Theme.accent).frame(width: geo.size.width * max(0, min(1, value)))
            }
        }
        .frame(width: 140, height: 6)
    }

    @ViewBuilder private var statusBadge: some View {
        switch testResult {
        case .testing: HStack(spacing: 6) { ProgressView().controlSize(.small); Text(L.t("Testing…", "Đang kiểm tra…")).font(.system(size: 11)).foregroundStyle(Theme.textSecondary) }
        case .ok: badge("OK", system: "checkmark.circle", fg: Theme.successFg, bg: Theme.successBg)
        case .fail(let m): badge(m, system: "xmark.circle", fg: Theme.textDanger, bg: Theme.bgDanger)
        case .none:
            if FileManager.default.isExecutableFile(atPath: settings.agyPath) {
                badge(L.t("Detected", "Đã dò thấy"), system: "checkmark.circle", fg: Theme.successFg, bg: Theme.successBg)
            } else {
                badge(L.t("Not found", "Không thấy"), system: "xmark.circle", fg: Theme.textDanger, bg: Theme.bgDanger)
            }
        }
    }

    private var quotaLabel: String {
        switch settings.quotaHitBehavior {
        case .pause: return L.t("Pause capture", "Tạm dừng capture")
        case .queue: return L.t("Queue", "Xếp hàng (queue)")
        case .skip: return L.t("Skip", "Bỏ qua")
        }
    }
    private var jsonErrorLabel: String {
        switch settings.jsonErrorBehavior {
        case .retryOnce: return L.t("Retry once", "Thử lại 1 lần")
        case .askAgain: return L.t("Ask agy again", "Hỏi agy lại")
        case .showRaw: return L.t("Show raw", "Hiện raw")
        }
    }

    private func setAppLanguage(_ lang: String) {
        settings.appLanguage = lang
        L.lang = lang
        persist()
        langTick += 1   // re-render this window immediately
    }

    /// Curated short list for the meaning-language picker. The system still accepts
    /// any code; this is just the common set surfaced in Settings.
    static let meaningLanguageCodes = ["vi", "en", "es", "fr", "de", "ja", "zh", "ko"]

    /// Native display name for a language code (autonym), e.g. "vi"→"Tiếng Việt",
    /// "ja"→"日本語". No hardcoded name table — derived from `Locale`.
    private func languageLabel(_ code: String) -> String {
        Locale(identifier: code).localizedString(forLanguageCode: code)?.capitalized ?? code
    }

    private func persist() {
        SettingsStore.save(settings)   // for next launch
        env.settings = settings         // apply live to open windows
    }

    private func runTest() {
        testResult = .testing
        let edited = settings
        Task {
            let client = AgyClient(settings: edited)
            do { _ = try await client.run(prompt: "Reply with the single word: OK", model: edited.model); testResult = .ok }
            catch { testResult = .fail(L.t("Failed", "Lỗi")) }
        }
    }
}

/// A settings row: label (+ optional sub) on the left, control on the right.
struct SettingsRow<Control: View>: View {
    let label: String
    var sub: String? = nil
    @ViewBuilder var control: Control

    init(_ label: String, sub: String? = nil, @ViewBuilder control: () -> Control) {
        self.label = label; self.sub = sub; self.control = control()
    }

    var body: some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 1) {
                Text(label).font(.system(size: 13)).foregroundStyle(Theme.textPrimary)
                if let sub { Text(sub).font(.system(size: 11)).foregroundStyle(Theme.textTertiary) }
            }
            Spacer()
            control
        }
        .padding(.horizontal, 14).padding(.vertical, 10)
        .overlay(alignment: .top) { Hairline() }
    }
}
