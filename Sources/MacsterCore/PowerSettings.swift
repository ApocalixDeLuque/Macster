import Foundation

/// A `pmset` setting that Macster 0.1 forced to 0 while it kept the Mac awake.
///
/// Macster 0.2 and later never change these settings. They matter only when undoing what the old version did.
public enum PowerKey: String, CaseIterable, Sendable {
    case sleep, disksleep, displaysleep, standby, powernap

    /// The values Macster is willing to pass to `pmset` when restoring this setting.
    public var allowedValues: ClosedRange<Int> {
        switch self {
        case .sleep, .disksleep, .displaysleep: 0...99_999 // minutes; 0 means never
        case .standby, .powernap: 0...1
        }
    }
}

/// Values for some or all of the `PowerKey` settings of one power source.
public struct PowerProfile: Equatable, Sendable {
    /// Only values inside each key's `allowedValues` are kept.
    public let values: [PowerKey: Int]

    public init(_ values: [PowerKey: Int] = [:]) {
        self.values = values.filter { key, value in key.allowedValues.contains(value) }
    }

    public subscript(key: PowerKey) -> Int? { values[key] }

    public var isEmpty: Bool { values.isEmpty }

    /// Arguments for `pmset -b` or `pmset -c`, in a fixed order: `["sleep", "1", "disksleep", "10", …]`.
    public var pmsetArguments: [String] {
        PowerKey.allCases.flatMap { key in
            values[key].map { [key.rawValue, String($0)] } ?? []
        }
    }

    /// Whether every setting still has the value Macster 0.1 forced while it was on.
    public var hasLegacyKeepAwakeValues: Bool {
        PowerKey.allCases.allSatisfy { values[$0] == 0 }
    }

    /// macOS defaults, used only when Macster 0.1 changed settings but left no backup of the originals.
    public static let batteryDefaults = PowerProfile([.sleep: 1, .disksleep: 10, .displaysleep: 2, .standby: 1, .powernap: 1])
    public static let powerAdapterDefaults = PowerProfile([.sleep: 1, .disksleep: 10, .displaysleep: 10, .standby: 1, .powernap: 1])
}

/// Settings for the battery and the power adapter.
public struct PowerSources: Equatable, Sendable {
    public var battery: PowerProfile?
    public var powerAdapter: PowerProfile?

    public init(battery: PowerProfile? = nil, powerAdapter: PowerProfile? = nil) {
        self.battery = battery
        self.powerAdapter = powerAdapter
    }

    public var isEmpty: Bool {
        (battery?.isEmpty ?? true) && (powerAdapter?.isEmpty ?? true)
    }

    /// Parses the output of `pmset -g custom`.
    ///
    /// Section headers start at the beginning of a line ("Battery Power:"); settings are indented below them.
    public init(pmsetCustomOutput output: String) {
        enum Section { case battery, powerAdapter, other }
        var section = Section.other
        var battery: [PowerKey: Int]?
        var powerAdapter: [PowerKey: Int]?

        for line in output.split(whereSeparator: \.isNewline) {
            let text = line.trimmingCharacters(in: .whitespaces)
            if let first = line.first, !first.isWhitespace {
                switch text {
                case "Battery Power:":
                    section = .battery
                    battery = battery ?? [:]
                case "AC Power:":
                    section = .powerAdapter
                    powerAdapter = powerAdapter ?? [:]
                default:
                    section = .other
                }
                continue
            }

            let fields = text.split(whereSeparator: \.isWhitespace)
            guard fields.count >= 2,
                  let key = PowerKey(rawValue: String(fields[0])),
                  let value = Int(fields[1])
            else { continue }

            switch section {
            case .battery: battery?[key] = value
            case .powerAdapter: powerAdapter?[key] = value
            case .other: break
            }
        }

        self.init(battery: battery.map(PowerProfile.init), powerAdapter: powerAdapter.map(PowerProfile.init))
    }
}
