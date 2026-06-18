import Foundation
import VokabKit

/// Persists `VokabSettings` as JSON in UserDefaults. The Settings UI (Phase 7)
/// reads and writes through here.
enum SettingsStore {
    private static let key = "vokab.settings.v1"

    static func load() -> VokabSettings {
        guard let data = UserDefaults.standard.data(forKey: key),
              let settings = try? JSONDecoder().decode(VokabSettings.self, from: data) else {
            return VokabSettings()
        }
        return settings
    }

    static func save(_ settings: VokabSettings) {
        if let data = try? JSONEncoder().encode(settings) {
            UserDefaults.standard.set(data, forKey: key)
        }
    }
}
