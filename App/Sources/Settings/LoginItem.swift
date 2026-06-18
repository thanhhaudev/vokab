import Foundation
import ServiceManagement

/// Launch-at-login via `SMAppService`. Reflects live system state — nothing is
/// stored in settings.
enum LoginItem {
    static var isEnabled: Bool { SMAppService.mainApp.status == .enabled }

    static func set(_ on: Bool) {
        do {
            if on { try SMAppService.mainApp.register() }
            else { try SMAppService.mainApp.unregister() }
        } catch {
            NSLog("vokab LoginItem error: \(error)")
        }
    }
}
