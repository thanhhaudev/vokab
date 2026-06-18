import AppKit
import Carbon.HIToolbox

/// Registers a system-wide hotkey via Carbon `RegisterEventHotKey` (no
/// Accessibility permission needed) and invokes `onTrigger` when pressed.
@MainActor
final class GlobalHotkey {
    static let shared = GlobalHotkey()

    var onTrigger: (() -> Void)?

    private var hotKeyRef: EventHotKeyRef?
    private var handlerRef: EventHandlerRef?
    private var installed = false

    /// Registers (replacing any prior). `keyCode` is a virtual key code;
    /// `modifiers` is an `NSEvent.ModifierFlags.rawValue` subset. No-op if keyCode is 0.
    func register(keyCode: Int, modifiers: Int) {
        unregister()
        guard keyCode != 0 else { return }
        installHandlerIfNeeded()
        let id = EventHotKeyID(signature: OSType(0x564B4220), id: 1)   // 'VKB '
        var ref: EventHotKeyRef?
        let status = RegisterEventHotKey(UInt32(keyCode), carbonModifiers(modifiers), id,
                                         GetApplicationEventTarget(), 0, &ref)
        if status == noErr { hotKeyRef = ref }
    }

    func unregister() {
        if let ref = hotKeyRef { UnregisterEventHotKey(ref); hotKeyRef = nil }
    }

    private func installHandlerIfNeeded() {
        guard !installed else { return }
        installed = true
        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard),
                                 eventKind: UInt32(kEventHotKeyPressed))
        let selfPtr = Unmanaged.passUnretained(self).toOpaque()
        InstallEventHandler(GetApplicationEventTarget(), { _, _, userData -> OSStatus in
            guard let userData else { return noErr }
            let manager = Unmanaged<GlobalHotkey>.fromOpaque(userData).takeUnretainedValue()
            DispatchQueue.main.async { manager.onTrigger?() }
            return noErr
        }, 1, &spec, selfPtr, &handlerRef)
    }

    private func carbonModifiers(_ cocoa: Int) -> UInt32 {
        let flags = NSEvent.ModifierFlags(rawValue: UInt(cocoa))
        var carbon: UInt32 = 0
        if flags.contains(.command) { carbon |= UInt32(cmdKey) }
        if flags.contains(.option)  { carbon |= UInt32(optionKey) }
        if flags.contains(.control) { carbon |= UInt32(controlKey) }
        if flags.contains(.shift)   { carbon |= UInt32(shiftKey) }
        return carbon
    }

    /// Human-readable label for a keyCode+modifiers, e.g. "⌥⌘V".
    static func label(keyCode: Int, modifiers: Int) -> String {
        guard keyCode != 0 else { return "—" }
        let flags = NSEvent.ModifierFlags(rawValue: UInt(modifiers))
        var s = ""
        if flags.contains(.control) { s += "⌃" }
        if flags.contains(.option)  { s += "⌥" }
        if flags.contains(.shift)   { s += "⇧" }
        if flags.contains(.command) { s += "⌘" }
        s += keyName(keyCode)
        return s
    }

    private static func keyName(_ keyCode: Int) -> String {
        let map: [Int: String] = [
            0: "A", 11: "B", 8: "C", 2: "D", 14: "E", 3: "F", 5: "G", 4: "H", 34: "I",
            38: "J", 40: "K", 37: "L", 46: "M", 45: "N", 31: "O", 35: "P", 12: "Q",
            15: "R", 1: "S", 17: "T", 32: "U", 9: "V", 13: "W", 7: "X", 16: "Y", 6: "Z",
            49: "Space", 36: "↩"
        ]
        return map[keyCode] ?? "key\(keyCode)"
    }
}
