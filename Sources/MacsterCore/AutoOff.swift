/// How long Macster keeps the Mac awake before turning itself off.
public struct AutoOff: Hashable, Sendable, Identifiable {
    /// Zero means never.
    public let minutes: Int

    public init(minutes: Int) {
        self.minutes = max(0, minutes)
    }

    public static let never = AutoOff(minutes: 0)
    public static let presets: [AutoOff] = [0, 30, 60, 120, 240, 480].map(AutoOff.init(minutes:))

    /// The presets, plus `current` if it was set to something else (for example with `defaults write`).
    public static func choices(including current: AutoOff) -> [AutoOff] {
        presets.contains(current) ? presets : (presets + [current]).sorted { $0.minutes < $1.minutes }
    }

    public var id: Int { minutes }

    public var isNever: Bool { minutes == 0 }

    public var duration: Duration? {
        isNever ? nil : .seconds(minutes * 60)
    }

    /// "Never", "30 minutes", "1 hour", "4 hours", "90 minutes".
    public var title: String {
        switch minutes {
        case 0: "Never"
        case 1: "1 minute"
        case 60: "1 hour"
        case let minutes where minutes % 60 == 0: "\(minutes / 60) hours"
        default: "\(minutes) minutes"
        }
    }
}
