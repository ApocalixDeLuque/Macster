/// A reading of the Mac's internal battery.
public struct BatteryReading: Equatable, Sendable {
    public var percent: Int
    public var isOnBatteryPower: Bool
    /// From the battery's own sensor, when the Mac reports one.
    public var temperatureCelsius: Double?

    public init(percent: Int, isOnBatteryPower: Bool, temperatureCelsius: Double? = nil) {
        self.percent = percent
        self.isOnBatteryPower = isOnBatteryPower
        self.temperatureCelsius = temperatureCelsius
    }
}

/// The charge at which Macster turns itself off while running on battery power.
public struct BatteryCutoff: Hashable, Sendable, Identifiable {
    /// Zero means never.
    public let percent: Int

    public init(percent: Int) {
        self.percent = min(max(0, percent), 95)
    }

    public static let never = BatteryCutoff(percent: 0)
    public static let standard = BatteryCutoff(percent: 10)
    public static let presets: [BatteryCutoff] = [0, 5, 10, 15, 20, 30].map(BatteryCutoff.init(percent:))

    /// The presets, plus `current` if it was set to something else (for example with `defaults write`).
    public static func choices(including current: BatteryCutoff) -> [BatteryCutoff] {
        presets.contains(current) ? presets : (presets + [current]).sorted { $0.percent < $1.percent }
    }

    public var id: Int { percent }

    public var isNever: Bool { percent == 0 }

    /// "Never", "10% battery".
    public var title: String {
        isNever ? "Never" : "\(percent)% battery"
    }
}

/// Rules for when Macster turns itself off to protect the Mac.
public enum Safety {
    /// Battery temperature at which the heat safety turns Macster off. Batteries stay well below this on a desk, even
    /// under load; a closed Mac working in a bag or sleeve climbs past it.
    public static let hotBatteryCelsius = 45.0

    /// The reason it isn't safe to keep the Mac awake right now, if there is one. Shared by the app, which turns off
    /// or refuses to turn on, and the `macster` command, which explains a refusal without waiting for one.
    public static func stopReason(
        battery: BatteryReading?,
        cutoff: BatteryCutoff,
        heatGuard: Bool,
        isOverheating: Bool
    ) -> TurnOffReason? {
        if let battery, isBatteryTooLow(battery, cutoff: cutoff) {
            return .lowBattery(percent: battery.percent)
        }
        guard heatGuard else { return nil }
        if isBatteryTooHot(battery), let celsius = battery?.temperatureCelsius {
            return .batteryHot(celsius: Int(celsius.rounded()))
        }
        return isOverheating ? .overheating : nil
    }

    public static func isBatteryTooLow(_ reading: BatteryReading?, cutoff: BatteryCutoff) -> Bool {
        guard let reading, reading.isOnBatteryPower, !cutoff.isNever else { return false }
        return reading.percent <= cutoff.percent
    }

    public static func isBatteryTooHot(_ reading: BatteryReading?) -> Bool {
        guard let celsius = reading?.temperatureCelsius else { return false }
        return celsius >= hotBatteryCelsius
    }

    /// The battery reports its temperature in hundredths of a degree Celsius. Nil for values no battery could have.
    public static func celsius(fromBatteryTemperature raw: Int) -> Double? {
        let celsius = Double(raw) / 100
        return (-20...120).contains(celsius) ? celsius : nil
    }
}

/// How Macster talks to `macster-watchdog` over the helper's stdin.
public enum WatchdogProtocol {
    public static let executableName = "macster-watchdog"
    /// Sent when Macster turned sleep back on itself, so the watchdog can exit without doing anything.
    public static let disarm = "disarm\n"
}
