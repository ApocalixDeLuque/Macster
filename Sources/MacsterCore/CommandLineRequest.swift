/// `macster <command>` in Terminal. Running the app's executable with no command launches the menu bar app.
public enum CommandLineRequest: Equatable, Sendable {
    /// Delivered to the running app as a `macster://` URL, launching it if needed.
    case send(MacsterCommand)
    /// Turn on, then replace this process with `command`. Macster stays on until it exits.
    case run([String])
    case status
    case diagnose
    case help
    case version

    public struct UsageError: Error, Equatable, CustomStringConvertible {
        public let description: String

        init(_ description: String) {
            self.description = description
        }
    }

    public static let usage = """
        Usage: macster <command>

          on [duration]        Keep your Mac awake, even with the lid closed. Duration: 45m, 2h, 1h30m, or never.
                               Without one, the "Turn off after" setting applies.
          off                  Let your Mac sleep normally again.
          toggle               Switch between on and off.
          run <command> ...    Stay awake until <command> exits, then turn off (if this turned it on).
          status               Print whether your Mac is being kept awake.
          open                 Show Macster's panel.
          diagnose             Print what Macster sees and what setup would do. Changes nothing.
          version              Print Macster's version.

        Examples:
          macster on 2h
          macster run -- make release
        """

    /// Nil when there is no command, or only flags macOS passes to apps it launches: start the menu bar app.
    public static func parse(_ arguments: [String]) throws(UsageError) -> CommandLineRequest? {
        guard let first = arguments.first else { return nil }
        let rest = Array(arguments.dropFirst())

        switch first {
        case "on":
            guard rest.count <= 1 else { throw UsageError("on takes at most one duration, like 2h.") }
            guard let text = rest.first else { return .send(.on(minutes: nil, pid: nil)) }
            guard let minutes = minutes(from: text) else {
                throw UsageError("'\(text)' isn't a duration. Use something like 45m, 2h, 1h30m, or never.")
            }
            guard minutes <= MacsterCommand.maximumMinutes else { throw UsageError("That's longer than a week.") }
            return .send(.on(minutes: minutes, pid: nil))
        case "off", "toggle", "open", "status", "diagnose", "--diagnose", "help", "--help", "-h", "version", "--version":
            guard rest.isEmpty else { throw UsageError("\(first) doesn't take arguments.") }
            switch first {
            case "off": return .send(.off)
            case "toggle": return .send(.toggle)
            case "open": return .send(.open)
            case "status": return .status
            case "diagnose", "--diagnose": return .diagnose
            case "version", "--version": return .version
            default: return .help
            }
        case "run":
            let command = rest.first == "--" ? Array(rest.dropFirst()) : rest
            guard let program = command.first, !program.isEmpty else {
                throw UsageError("run needs a command, like: macster run -- make release")
            }
            return .run(command)
        default:
            // LaunchServices and Xcode pass flags such as -psn_0_1234 or -NSDocumentRevisionsDebugMode YES.
            if first.hasPrefix("-") { return nil }
            throw UsageError("Unknown command '\(first)'. Run 'macster help'.")
        }
    }

    /// "90", "90m", "2h", "1h30m", "1h30", "never". Never is zero: no timer.
    public static func minutes(from text: String) -> Int? {
        let text = text.lowercased()
        if ["never", "forever", "indefinitely"].contains(text) { return 0 }

        var total = 0
        var number = ""
        var sawHours = false
        var sawMinutes = false
        for character in text {
            if character.isASCII, character.isNumber {
                number.append(character)
                guard number.count <= 6 else { return nil }
            } else if character == "h", !sawHours, !sawMinutes, let value = Int(number) {
                total += value * 60
                number = ""
                sawHours = true
            } else if character == "m", !sawMinutes, let value = Int(number) {
                total += value
                number = ""
                sawMinutes = true
            } else {
                return nil
            }
        }
        if !number.isEmpty {
            // A bare number is minutes; after hours ("1h30") too.
            guard !sawMinutes, let value = Int(number) else { return nil }
            total += value
        } else if !sawHours, !sawMinutes {
            return nil
        }
        return total
    }
}
