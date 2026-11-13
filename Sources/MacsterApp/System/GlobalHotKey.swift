import AppKit
import Carbon.HIToolbox
import MacsterCore

/// A system-wide keyboard shortcut through Carbon's hot key API. Unlike event monitors, it needs no Accessibility or
/// Input Monitoring permission, and macOS hands Macster only this one key combination, never other typing.
///
/// Lives as long as the app: the event handler keeps an unretained pointer to it.
final class GlobalHotKey {
    private var hotKey: EventHotKeyRef?
    private var handler: EventHandlerRef?
    private var action: (() -> Void)?

    private static let signature: OSType = 0x4D43_5354 // "MCST"

    /// Registers `shortcut` in place of any previous one. False if macOS refused it, usually because it's taken.
    func register(_ shortcut: KeyboardShortcut, action: @escaping () -> Void) -> Bool {
        unregister()
        installHandlerIfNeeded()
        var reference: EventHotKeyRef?
        let status = RegisterEventHotKey(
            UInt32(shortcut.keyCode),
            shortcut.carbonModifiers,
            EventHotKeyID(signature: Self.signature, id: 1),
            GetApplicationEventTarget(),
            0,
            &reference
        )
        guard status == noErr, let reference else { return false }
        hotKey = reference
        self.action = action
        return true
    }

    func unregister() {
        if let hotKey {
            UnregisterEventHotKey(hotKey)
        }
        hotKey = nil
        action = nil
    }

    private func installHandlerIfNeeded() {
        guard handler == nil else { return }
        var pressed = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        let context = Unmanaged.passUnretained(self).toOpaque()
        InstallEventHandler(GetApplicationEventTarget(), hotKeyPressed, 1, &pressed, context, &handler)
    }

    fileprivate func fire() {
        action?()
    }
}

/// Carbon delivers hot key events on the main thread, through the application's event target.
private nonisolated func hotKeyPressed(
    _ next: EventHandlerCallRef?,
    _ event: EventRef?,
    _ context: UnsafeMutableRawPointer?
) -> OSStatus {
    let address = UInt(bitPattern: context)
    MainActor.assumeIsolated {
        guard let context = UnsafeMutableRawPointer(bitPattern: address) else { return }
        Unmanaged<GlobalHotKey>.fromOpaque(context).takeUnretainedValue().fire()
    }
    return noErr
}

extension KeyboardShortcut {
    /// "⌃⌥⌘L", with the key as the current keyboard layout labels it.
    var title: String {
        displayName(character: KeyLayout.character(for: keyCode))
    }

    init(event: NSEvent) {
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        var modifiers: Modifiers = []
        if flags.contains(.control) { modifiers.insert(.control) }
        if flags.contains(.option) { modifiers.insert(.option) }
        if flags.contains(.shift) { modifiers.insert(.shift) }
        if flags.contains(.command) { modifiers.insert(.command) }
        self.init(keyCode: event.keyCode, modifiers: modifiers)
    }

    /// The key equivalent a menu item shows for this shortcut, if it can show one.
    var menuKeyEquivalent: (key: String, modifiers: NSEvent.ModifierFlags)? {
        let functionKeys: [UInt16: Int] = [
            122: NSF1FunctionKey, 120: NSF2FunctionKey, 99: NSF3FunctionKey, 118: NSF4FunctionKey,
            96: NSF5FunctionKey, 97: NSF6FunctionKey, 98: NSF7FunctionKey, 100: NSF8FunctionKey,
            101: NSF9FunctionKey, 109: NSF10FunctionKey, 103: NSF11FunctionKey, 111: NSF12FunctionKey,
            105: NSF13FunctionKey, 107: NSF14FunctionKey, 113: NSF15FunctionKey, 106: NSF16FunctionKey,
            64: NSF17FunctionKey, 79: NSF18FunctionKey, 80: NSF19FunctionKey, 90: NSF20FunctionKey,
            123: NSLeftArrowFunctionKey, 124: NSRightArrowFunctionKey, 125: NSDownArrowFunctionKey,
            126: NSUpArrowFunctionKey, 115: NSHomeFunctionKey, 119: NSEndFunctionKey,
            116: NSPageUpFunctionKey, 121: NSPageDownFunctionKey, 117: NSDeleteFunctionKey,
        ]
        let fixed: [UInt16: String] = [36: "\r", 48: "\t", 49: " ", 51: "\u{8}", 53: "\u{1b}"]

        let key: String
        if let code = functionKeys[keyCode], let scalar = UnicodeScalar(code) {
            key = String(Character(scalar))
        } else if let text = fixed[keyCode] {
            key = text
        } else if let character = KeyLayout.character(for: keyCode), !character.isEmpty {
            key = character.lowercased()
        } else {
            return nil
        }

        var flags: NSEvent.ModifierFlags = []
        if modifiers.contains(.control) { flags.insert(.control) }
        if modifiers.contains(.option) { flags.insert(.option) }
        if modifiers.contains(.shift) { flags.insert(.shift) }
        if modifiers.contains(.command) { flags.insert(.command) }
        return (key, flags)
    }
}

/// What keys type on the current keyboard layout.
enum KeyLayout {
    /// The character `keyCode` types without modifiers, like "l" on U.S. English or "ñ" on Spanish.
    static func character(for keyCode: UInt16) -> String? {
        for copy in [TISCopyCurrentKeyboardLayoutInputSource, TISCopyCurrentASCIICapableKeyboardLayoutInputSource] {
            guard let source = copy()?.takeRetainedValue(),
                  let property = TISGetInputSourceProperty(source, kTISPropertyUnicodeKeyLayoutData)
            else { continue }
            let data = Unmanaged<CFData>.fromOpaque(property).takeUnretainedValue()
            guard let bytes = CFDataGetBytePtr(data) else { continue }

            var deadKeyState: UInt32 = 0
            var length = 0
            var characters = [UniChar](repeating: 0, count: 4)
            let status = bytes.withMemoryRebound(to: UCKeyboardLayout.self, capacity: 1) { layout in
                UCKeyTranslate(
                    layout,
                    keyCode,
                    UInt16(kUCKeyActionDisplay),
                    0,
                    UInt32(LMGetKbdType()),
                    OptionBits(kUCKeyTranslateNoDeadKeysBit),
                    &deadKeyState,
                    characters.count,
                    &length,
                    &characters
                )
            }
            guard status == noErr, length > 0 else { continue }
            let text = String(utf16CodeUnits: characters, count: length)
            // Keys that type control characters (Return, Tab, arrows) have names of their own.
            return text.unicodeScalars.allSatisfy { $0.properties.generalCategory == .control } ? nil : text
        }
        return nil
    }
}
