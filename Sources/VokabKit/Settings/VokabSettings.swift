import Foundation

/// What to do when the daily agy quota is reached (SPEC §9).
public enum QuotaHitBehavior: String, Codable, Sendable, CaseIterable {
    case pause      // stop capturing until reset
    case queue      // enqueue and run later
    case skip       // drop this capture
}

/// What to do when agy returns undecodable JSON (SPEC §10).
public enum JSONErrorBehavior: String, Codable, Sendable, CaseIterable {
    case retryOnce  // re-run the same prompt once (default)
    case askAgain   // re-run (reserved for a future corrective re-prompt)
    case showRaw    // surface the raw output, do not retry
}

/// App appearance preference (Settings → General). `.system` follows macOS.
public enum AppearanceMode: String, Codable, Sendable, CaseIterable {
    case system
    case light
    case dark
}

/// User-configurable settings (Settings tabs, SPEC §13). Plain value type so it
/// is trivially testable and `Sendable`. Decoding is resilient: missing keys
/// fall back to defaults so adding fields never breaks older persisted JSON.
public struct VokabSettings: Codable, Sendable, Equatable {
    // AI Engine
    public var agyPath: String
    public var model: String?
    /// Faster model used for lazy enrichment (background, lower-stakes).
    public var enrichModel: String?
    public var timeoutSeconds: Int
    public var dailyLimit: Int
    /// Khi true, vượt `dailyLimit` sẽ CHẶN capture (theo quotaHitBehavior). Mặc định chỉ cảnh báo.
    public var hardBlockOnLimit: Bool
    public var meaningLanguage: String
    public var appLanguage: String
    public var quotaHitBehavior: QuotaHitBehavior
    public var jsonErrorBehavior: JSONErrorBehavior
    public var maxConcurrent: Int
    public var minParagraphLevel: CEFR
    // General
    public var toastPosition: ToastCorner
    public var globalHotkeyEnabled: Bool
    public var globalHotkeyKeyCode: Int
    public var globalHotkeyModifiers: Int
    public var pronunciationAccent: String
    public var autoPlayPronunciation: Bool
    public var appearanceMode: AppearanceMode
    // Review
    public var newCardsPerDay: Int
    public var productionUnlockInterval: Int
    public var productionUnlockReps: Int
    public var clozeUnlockInterval: Int
    public var clozeUnlockReps: Int
    public var errorUnlockInterval: Int
    public var errorUnlockReps: Int
    public var listeningAudioFront: Bool
    public var listeningUnlockInterval: Int
    public var listeningUnlockReps: Int
    public var startingEase: Double
    // Capture
    public var autoDetectLanguage: Bool
    public var defaultCaptureLanguage: String

    public init(
        agyPath: String = VokabSettings.defaultAgyPath,
        model: String? = nil,
        enrichModel: String? = nil,
        timeoutSeconds: Int = 60,
        dailyLimit: Int = 200,
        hardBlockOnLimit: Bool = false,
        meaningLanguage: String = "vi",
        appLanguage: String = "en",
        quotaHitBehavior: QuotaHitBehavior = .queue,
        jsonErrorBehavior: JSONErrorBehavior = .retryOnce,
        maxConcurrent: Int = 3,
        minParagraphLevel: CEFR = .b1,
        toastPosition: ToastCorner = .topTrailing,
        globalHotkeyEnabled: Bool = false,
        globalHotkeyKeyCode: Int = 0,
        globalHotkeyModifiers: Int = 0,
        pronunciationAccent: String = "en-US",
        autoPlayPronunciation: Bool = false,
        appearanceMode: AppearanceMode = .system,
        newCardsPerDay: Int = 20,
        productionUnlockInterval: Int = 7,
        productionUnlockReps: Int = 2,
        clozeUnlockInterval: Int = 3,
        clozeUnlockReps: Int = 2,
        errorUnlockInterval: Int = 5,
        errorUnlockReps: Int = 2,
        listeningAudioFront: Bool = true,
        listeningUnlockInterval: Int = 1,
        listeningUnlockReps: Int = 2,
        startingEase: Double = 2.5,
        autoDetectLanguage: Bool = true,
        defaultCaptureLanguage: String = "en"
    ) {
        self.agyPath = agyPath
        self.model = model
        self.enrichModel = enrichModel
        self.timeoutSeconds = timeoutSeconds
        self.dailyLimit = dailyLimit
        self.hardBlockOnLimit = hardBlockOnLimit
        self.meaningLanguage = meaningLanguage
        self.appLanguage = appLanguage
        self.quotaHitBehavior = quotaHitBehavior
        self.jsonErrorBehavior = jsonErrorBehavior
        self.maxConcurrent = maxConcurrent
        self.minParagraphLevel = minParagraphLevel
        self.toastPosition = toastPosition
        self.globalHotkeyEnabled = globalHotkeyEnabled
        self.globalHotkeyKeyCode = globalHotkeyKeyCode
        self.globalHotkeyModifiers = globalHotkeyModifiers
        self.pronunciationAccent = pronunciationAccent
        self.autoPlayPronunciation = autoPlayPronunciation
        self.appearanceMode = appearanceMode
        self.newCardsPerDay = newCardsPerDay
        self.productionUnlockInterval = productionUnlockInterval
        self.productionUnlockReps = productionUnlockReps
        self.clozeUnlockInterval = clozeUnlockInterval
        self.clozeUnlockReps = clozeUnlockReps
        self.errorUnlockInterval = errorUnlockInterval
        self.errorUnlockReps = errorUnlockReps
        self.listeningAudioFront = listeningAudioFront
        self.listeningUnlockInterval = listeningUnlockInterval
        self.listeningUnlockReps = listeningUnlockReps
        self.startingEase = startingEase
        self.autoDetectLanguage = autoDetectLanguage
        self.defaultCaptureLanguage = defaultCaptureLanguage
    }

    private enum CodingKeys: String, CodingKey {
        case agyPath, model, enrichModel, timeoutSeconds, dailyLimit, hardBlockOnLimit, meaningLanguage, appLanguage
        case quotaHitBehavior, jsonErrorBehavior, maxConcurrent, minParagraphLevel
        case toastPosition, globalHotkeyEnabled, globalHotkeyKeyCode, globalHotkeyModifiers
        case pronunciationAccent, autoPlayPronunciation, appearanceMode
        case newCardsPerDay, productionUnlockInterval, productionUnlockReps, startingEase
        case clozeUnlockInterval, clozeUnlockReps
        case errorUnlockInterval, errorUnlockReps
        case listeningAudioFront, listeningUnlockInterval, listeningUnlockReps
        case autoDetectLanguage, defaultCaptureLanguage
    }

    /// Resilient decode: every key falls back to its default when absent.
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = VokabSettings()   // defaults
        agyPath = (try? c.decodeIfPresent(String.self, forKey: .agyPath)) ?? nil ?? d.agyPath
        model = (try? c.decodeIfPresent(String.self, forKey: .model)) ?? nil
        // Missing key → new default; present (even null) → that value.
        enrichModel = c.contains(.enrichModel)
            ? ((try? c.decodeIfPresent(String.self, forKey: .enrichModel)) ?? nil)
            : d.enrichModel
        timeoutSeconds = (try? c.decodeIfPresent(Int.self, forKey: .timeoutSeconds)) ?? nil ?? d.timeoutSeconds
        dailyLimit = (try? c.decodeIfPresent(Int.self, forKey: .dailyLimit)) ?? nil ?? d.dailyLimit
        hardBlockOnLimit = (try? c.decodeIfPresent(Bool.self, forKey: .hardBlockOnLimit)) ?? nil ?? d.hardBlockOnLimit
        meaningLanguage = (try? c.decodeIfPresent(String.self, forKey: .meaningLanguage)) ?? nil ?? d.meaningLanguage
        appLanguage = (try? c.decodeIfPresent(String.self, forKey: .appLanguage)) ?? nil ?? d.appLanguage
        quotaHitBehavior = (try? c.decodeIfPresent(QuotaHitBehavior.self, forKey: .quotaHitBehavior)) ?? nil ?? d.quotaHitBehavior
        jsonErrorBehavior = (try? c.decodeIfPresent(JSONErrorBehavior.self, forKey: .jsonErrorBehavior)) ?? nil ?? d.jsonErrorBehavior
        maxConcurrent = (try? c.decodeIfPresent(Int.self, forKey: .maxConcurrent)) ?? nil ?? d.maxConcurrent
        minParagraphLevel = (try? c.decodeIfPresent(CEFR.self, forKey: .minParagraphLevel)) ?? nil ?? d.minParagraphLevel
        toastPosition = (try? c.decodeIfPresent(ToastCorner.self, forKey: .toastPosition)) ?? nil ?? d.toastPosition
        globalHotkeyEnabled = (try? c.decodeIfPresent(Bool.self, forKey: .globalHotkeyEnabled)) ?? nil ?? d.globalHotkeyEnabled
        globalHotkeyKeyCode = (try? c.decodeIfPresent(Int.self, forKey: .globalHotkeyKeyCode)) ?? nil ?? d.globalHotkeyKeyCode
        globalHotkeyModifiers = (try? c.decodeIfPresent(Int.self, forKey: .globalHotkeyModifiers)) ?? nil ?? d.globalHotkeyModifiers
        pronunciationAccent = (try? c.decodeIfPresent(String.self, forKey: .pronunciationAccent)) ?? nil ?? d.pronunciationAccent
        autoPlayPronunciation = (try? c.decodeIfPresent(Bool.self, forKey: .autoPlayPronunciation)) ?? nil ?? d.autoPlayPronunciation
        appearanceMode = (try? c.decodeIfPresent(AppearanceMode.self, forKey: .appearanceMode)) ?? nil ?? d.appearanceMode
        newCardsPerDay = (try? c.decodeIfPresent(Int.self, forKey: .newCardsPerDay)) ?? nil ?? d.newCardsPerDay
        productionUnlockInterval = (try? c.decodeIfPresent(Int.self, forKey: .productionUnlockInterval)) ?? nil ?? d.productionUnlockInterval
        productionUnlockReps = (try? c.decodeIfPresent(Int.self, forKey: .productionUnlockReps)) ?? nil ?? d.productionUnlockReps
        clozeUnlockInterval = (try? c.decodeIfPresent(Int.self, forKey: .clozeUnlockInterval)) ?? nil ?? d.clozeUnlockInterval
        clozeUnlockReps = (try? c.decodeIfPresent(Int.self, forKey: .clozeUnlockReps)) ?? nil ?? d.clozeUnlockReps
        errorUnlockInterval = (try? c.decodeIfPresent(Int.self, forKey: .errorUnlockInterval)) ?? nil ?? d.errorUnlockInterval
        errorUnlockReps = (try? c.decodeIfPresent(Int.self, forKey: .errorUnlockReps)) ?? nil ?? d.errorUnlockReps
        listeningAudioFront = (try? c.decodeIfPresent(Bool.self, forKey: .listeningAudioFront)) ?? nil ?? d.listeningAudioFront
        listeningUnlockInterval = (try? c.decodeIfPresent(Int.self, forKey: .listeningUnlockInterval)) ?? nil ?? d.listeningUnlockInterval
        listeningUnlockReps = (try? c.decodeIfPresent(Int.self, forKey: .listeningUnlockReps)) ?? nil ?? d.listeningUnlockReps
        startingEase = (try? c.decodeIfPresent(Double.self, forKey: .startingEase)) ?? nil ?? d.startingEase
        autoDetectLanguage = (try? c.decodeIfPresent(Bool.self, forKey: .autoDetectLanguage)) ?? nil ?? d.autoDetectLanguage
        defaultCaptureLanguage = (try? c.decodeIfPresent(String.self, forKey: .defaultCaptureLanguage)) ?? nil ?? d.defaultCaptureLanguage
    }

    /// Default agy install location (`~/.local/bin/agy`).
    public static var defaultAgyPath: String {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        return "\(home)/.local/bin/agy"
    }
}
