/// A global keyboard shortcut: one key plus modifier keys.
public struct KeyboardShortcut: Hashable, Sendable, Codable {
    public struct Modifiers: OptionSet, Hashable, Sendable, Codable {
        public let rawValue: Int

        public init(rawValue: Int) {
            self.rawValue = rawValue
        }

        public static let control = Modifiers(rawValue: 1 << 0)
        public static let option = Modifiers(rawValue: 1 << 1)
        public static let shift = Modifiers(rawValue: 1 << 2)
        public static let command = Modifiers(rawValue: 1 << 3)

        /// In the order macOS shows them: ⌃⌥⇧⌘.
        static let ordered: [(Modifiers, symbol: String)] = [(.control, "⌃"), (.option, "⌥"), (.shift, "⇧"), (.command, "⌘")]

        var count: Int { Self.ordered.count { contains($0.0) } }
    }

    /// A virtual key code (`kVK_*`): the key's position, independent of the keyboard layout.
    public var keyCode: UInt16
    public var modifiers: Modifiers

    public init(keyCode: UInt16, modifiers: Modifiers) {
        self.keyCode = keyCode
        self.modifiers = modifiers
    }

    public enum Problem: Equatable, Sendable {
        /// Single modifiers collide with typing (⌥ types accents and symbols), Terminal (⌃C), and app shortcuts (⌘Q).
        case needsMoreModifiers
    }

    /// Why this can't be a global shortcut, or nil if it can.
    public var problem: Problem? {
        if Self.functionKeyNumbers[keyCode] != nil { return nil }
        let hasCommandOrControl = modifiers.contains(.command) || modifiers.contains(.control)
        return hasCommandOrControl && modifiers.count >= 2 ? nil : .needsMoreModifiers
    }

    /// Modifier flags for Carbon's `RegisterEventHotKey`: cmdKey, shiftKey, optionKey, controlKey.
    public var carbonModifiers: UInt32 {
        var flags: UInt32 = 0
        if modifiers.contains(.command) { flags |= 0x0100 }
        if modifiers.contains(.shift) { flags |= 0x0200 }
        if modifiers.contains(.option) { flags |= 0x0800 }
        if modifiers.contains(.control) { flags |= 0x1000 }
        return flags
    }

    public var modifierSymbols: String {
        Modifiers.ordered.filter { modifiers.contains($0.0) }.map(\.symbol).joined()
    }

    /// "⌃⌥⌘L". `character` is what the key types on the current layout; keys that don't type one have fixed names.
    public func displayName(character: String?) -> String {
        let key = Self.specialKeyNames[keyCode]
            ?? character.map { $0.uppercased() }.flatMap { $0.isEmpty ? nil : $0 }
            ?? "Key \(keyCode)"
        return modifierSymbols + key
    }

    public var isFunctionKey: Bool { Self.functionKeyNumbers[keyCode] != nil }

    // Virtual key codes from Carbon's Events.h.
    public static let escapeKeyCode: UInt16 = 53
    public static let deleteKeyCodes: Set<UInt16> = [51, 117]

    static let functionKeyNumbers: [UInt16: Int] = [
        122: 1, 120: 2, 99: 3, 118: 4, 96: 5, 97: 6, 98: 7, 100: 8, 101: 9, 109: 10,
        103: 11, 111: 12, 105: 13, 107: 14, 113: 15, 106: 16, 64: 17, 79: 18, 80: 19, 90: 20,
    ]

    static let specialKeyNames: [UInt16: String] = {
        var names: [UInt16: String] = [
            36: "↩", 48: "⇥", 49: "Space", 51: "⌫", 53: "⎋", 117: "⌦", 76: "⌤",
            115: "↖", 119: "↘", 116: "⇞", 121: "⇟", 123: "←", 124: "→", 125: "↓", 126: "↑",
        ]
        for (code, number) in functionKeyNumbers {
            names[code] = "F\(number)"
        }
        return names
    }()
}
