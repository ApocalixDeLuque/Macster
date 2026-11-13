/// The only privileged commands Macster runs after setup.
public enum SleepCommand {
    public static let sudoPath = "/usr/bin/sudo"
    public static let pmsetPath = "/usr/bin/pmset"

    /// `pmset -a disablesleep 1` keeps the Mac awake for every reason, closing the lid included.
    /// `pmset -a disablesleep 0` lets it sleep normally again. Nothing else about power settings changes.
    public static func pmsetArguments(sleepDisabled: Bool) -> [String] {
        ["-a", "disablesleep", sleepDisabled ? "1" : "0"]
    }

    /// `sudo -n` never prompts: it fails right away if Macster's rule is missing.
    public static func sudoArguments(sleepDisabled: Bool) -> [String] {
        ["-n", pmsetPath] + pmsetArguments(sleepDisabled: sleepDisabled)
    }

    /// The command exactly as it appears in the sudo rule.
    public static func commandLine(sleepDisabled: Bool) -> String {
        ([pmsetPath] + pmsetArguments(sleepDisabled: sleepDisabled)).joined(separator: " ")
    }
}

/// The sudoers rule that lets one user run exactly the two `SleepCommand`s as root without a password.
public struct SudoRule: Equatable, Sendable {
    public static let path = "/private/etc/sudoers.d/macster"

    public enum Problem: Error, Equatable {
        case invalidUserName(String)
    }

    public let userName: String

    public init(userName: String) throws(Problem) {
        guard Self.isValidUserName(userName) else { throw .invalidUserName(userName) }
        self.userName = userName
    }

    /// macOS account short names: ASCII letters, digits, `_`, `.` and `-`, not starting with `-` or `.`.
    /// Anything else is refused rather than escaped, because the name is written into a sudoers file.
    public static func isValidUserName(_ name: String) -> Bool {
        let scalars = name.unicodeScalars
        guard (1...64).contains(scalars.count), let first = scalars.first, first != "-", first != "." else {
            return false
        }
        return scalars.allSatisfy { scalar in
            switch scalar {
            case "a"..."z", "A"..."Z", "0"..."9", "_", ".", "-": true
            default: false
            }
        }
    }

    public var contents: String {
        let on = SleepCommand.commandLine(sleepDisabled: true)
        let off = SleepCommand.commandLine(sleepDisabled: false)
        return """
        # Added by Macster so \(userName) can turn lid-close sleep on and off without a password.
        # It allows exactly these two commands and nothing else. Delete this file to revoke it.
        \(userName) ALL=(root) NOPASSWD: \(on), \(off)

        """
    }

    /// Whether the output of `sudo -n -l` shows that both commands can run as root without a password.
    ///
    /// Privilege lines look like `(root) NOPASSWD: /usr/bin/pmset -a disablesleep 1, /usr/bin/pmset -a disablesleep 0`.
    /// Tags such as `NOPASSWD:` apply to the command they precede and every command after it on the line.
    public static func listingGrantsAccess(_ listing: String) -> Bool {
        let required: Set<String> = [
            SleepCommand.commandLine(sleepDisabled: true),
            SleepCommand.commandLine(sleepDisabled: false),
        ]
        var granted = Set<String>()

        for rawLine in listing.split(whereSeparator: \.isNewline) {
            let line = rawLine.drop(while: \.isWhitespace)
            guard line.first == "(", let close = line.firstIndex(of: ")") else { continue }

            let runAs = line[line.index(after: line.startIndex)..<close]
            let runAsUsers = runAs.split(separator: ":", maxSplits: 1).first?
                .split(separator: ",")
                .map { $0.trimmingWhitespace() } ?? []
            guard runAsUsers.contains("root") || runAsUsers.contains("ALL") else { continue }

            var passwordless = false
            for item in line[line.index(after: close)...].split(separator: ",") {
                var command = item.trimmingWhitespace()[...]
                while let colon = command.firstIndex(of: ":") {
                    let tag = command[..<colon]
                    guard !tag.isEmpty, tag.allSatisfy({ $0.isUppercase || $0 == "_" }) else { break }
                    if tag == "NOPASSWD" { passwordless = true }
                    if tag == "PASSWD" { passwordless = false }
                    command = command[command.index(after: colon)...].drop(while: \.isWhitespace)
                }
                guard passwordless else { continue }
                if command == "ALL" { return true }
                granted.insert(String(command))
            }
        }
        return required.isSubset(of: granted)
    }
}

extension SudoRule.Problem: CustomStringConvertible {
    public var description: String {
        switch self {
        case .invalidUserName(let name):
            "Macster can't set itself up for the macOS account name “\(name)”."
        }
    }
}

extension StringProtocol {
    func trimmingWhitespace() -> String {
        String(drop(while: \.isWhitespace).reversed().drop(while: \.isWhitespace).reversed())
    }
}
