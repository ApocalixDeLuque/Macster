import Foundation

/// What Shortcuts, other apps and the `macster` command can ask Macster to do, as `macster://` URLs.
///
///     macster://on                 turn on, with the "Turn off after" setting
///     macster://on?minutes=90      turn on for 90 minutes (or hours=2); minutes=0 means no timer
///     macster://on?pid=4242        turn on until process 4242 exits
///     macster://off
///     macster://toggle
///     macster://open               show the panel
public enum MacsterCommand: Equatable, Sendable {
    case on(minutes: Int?, pid: Int32?)
    case off
    case toggle
    case open

    public static let scheme = "macster"

    /// A week. Longer timers are almost certainly typos.
    public static let maximumMinutes = 7 * 24 * 60

    public init?(url: URL) {
        guard url.scheme?.lowercased() == Self.scheme,
              let components = URLComponents(url: url, resolvingAgainstBaseURL: false)
        else { return nil }

        // macster://on puts the name in the host; macster:on and macster:///on put it in the path.
        let host = components.host ?? ""
        let name = (host.isEmpty ? components.path : host)
            .trimmingCharacters(in: CharacterSet(charactersIn: "/"))
            .lowercased()

        var parameters: [String: String] = [:]
        for item in components.queryItems ?? [] {
            parameters[item.name.lowercased()] = item.value ?? ""
        }

        switch name {
        case "on":
            var minutes: Int?
            if let value = parameters["minutes"] {
                guard let parsed = Int(value) else { return nil }
                minutes = parsed
            }
            if let value = parameters["hours"] {
                guard let hours = Int(value), hours <= Self.maximumMinutes / 60 else { return nil }
                minutes = (minutes ?? 0) + hours * 60
            }
            if let minutes, !(0...Self.maximumMinutes).contains(minutes) { return nil }

            var pid: Int32?
            if let value = parameters["pid"] {
                guard let parsed = Int32(value), parsed > 0 else { return nil }
                pid = parsed
            }
            self = .on(minutes: minutes, pid: pid)
        case "off":
            self = .off
        case "toggle":
            self = .toggle
        case "open", "":
            self = .open
        default:
            return nil
        }
    }

    public var url: URL {
        var components = URLComponents()
        components.scheme = Self.scheme
        switch self {
        case .on(let minutes, let pid):
            components.host = "on"
            var items: [URLQueryItem] = []
            if let minutes { items.append(URLQueryItem(name: "minutes", value: String(minutes))) }
            if let pid { items.append(URLQueryItem(name: "pid", value: String(pid))) }
            components.queryItems = items.isEmpty ? nil : items
        case .off:
            components.host = "off"
        case .toggle:
            components.host = "toggle"
        case .open:
            components.host = "open"
        }
        return components.url!
    }
}

extension MacsterCommand: CustomStringConvertible {
    public var description: String { url.absoluteString }
}
