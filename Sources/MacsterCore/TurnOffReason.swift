/// Why Macster turned itself off.
public enum TurnOffReason: Equatable, Sendable {
    case timerEnded(AutoOff)
    case lowBattery(percent: Int)
    case batteryHot(celsius: Int)
    case overheating
    case helperKeptStopping
    case leftOverSession
    case commandsFinished

    /// Shown in the panel.
    public var message: String {
        switch self {
        case .timerEnded(let autoOff):
            "Turned off after \(autoOff.title)."
        case .lowBattery(let percent):
            "Turned off at \(percent)% battery so your Mac can sleep instead of running out."
        case .batteryHot(let celsius):
            "Turned off because the battery reached \(celsius) °C. Let your Mac cool down."
        case .overheating:
            "Turned off because your Mac was overheating."
        case .helperKeptStopping:
            "Turned off because Macster’s safety helper kept stopping."
        case .leftOverSession:
            "Turned off: Macster didn’t quit normally last time."
        case .commandsFinished:
            "Turned off because the command it was waiting for finished."
        }
    }

    /// Why Macster won't turn on while a safety would stop it right away.
    public var refusal: String {
        switch self {
        case .lowBattery(let percent):
            "Your battery is at \(percent)%. Plug in your Mac, or lower the battery setting below."
        case .batteryHot(let celsius):
            "Your Mac’s battery is at \(celsius) °C. Let it cool down, or turn off the heat safety below."
        case .overheating:
            "Your Mac is overheating. Let it cool down, or turn off the heat safety below."
        case .timerEnded, .helperKeptStopping, .leftOverSession, .commandsFinished:
            message
        }
    }

    /// The body of a notification, for reasons worth one. Nil when the turn-off is what the user asked for.
    public var notificationBody: String? {
        switch self {
        case .timerEnded(let autoOff):
            "Macster turned off after \(autoOff.title)."
        case .lowBattery(let percent):
            "Macster turned off at \(percent)% battery so your Mac can sleep instead of running out."
        case .batteryHot(let celsius):
            "Macster turned off because the battery reached \(celsius) °C."
        case .overheating:
            "Macster turned off because your Mac was overheating."
        case .helperKeptStopping:
            "Macster turned off because its safety helper kept stopping."
        case .leftOverSession:
            "Macster didn’t quit normally last time, so it turned normal sleep back on."
        case .commandsFinished:
            nil
        }
    }
}
