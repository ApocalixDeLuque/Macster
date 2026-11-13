import Foundation

/// Quoting for the two languages a privileged script passes through on its way to `/bin/sh`.
public enum Quoting {
    /// A POSIX shell word that the shell reads back as exactly `text`.
    public static func shell(_ text: String) -> String {
        "'" + text.replacingOccurrences(of: "'", with: #"'\''"#) + "'"
    }

    /// An AppleScript string literal that AppleScript reads back as exactly `text`.
    public static func appleScript(_ text: String) -> String {
        let escaped = text
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
        return "\"" + escaped + "\""
    }
}

/// A shell script that runs as root behind macOS's standard administrator password prompt.
///
/// The script travels as a single argument (`/bin/sh -c '<script>'`) inside an AppleScript string, so it never
/// touches the disk and no temporary file can be swapped out before it runs.
public struct PrivilegedScript: Equatable, Sendable {
    public var script: String
    public var prompt: String

    public init(script: String, prompt: String) {
        self.script = script
        self.prompt = prompt
    }

    /// Source for `osascript -e`. Tests pass `false` to run the same quoting without a password prompt.
    public func appleScript(withAdministratorPrivileges: Bool = true) -> String {
        let command = "/bin/sh -c \(Quoting.shell(script)) macster"
        var source = "do shell script \(Quoting.appleScript(command))"
        if withAdministratorPrivileges {
            source += " with prompt \(Quoting.appleScript(prompt)) with administrator privileges"
        }
        return source
    }

    /// Whether `osascript` failed because the user dismissed the password prompt.
    public static func isCancellation(_ osascriptError: String) -> Bool {
        osascriptError.contains("(-128)")
    }

    /// The readable part of an `osascript` error such as `0:120: execution error: something failed (1)`.
    public static func message(fromOsascriptError error: String) -> String {
        var text = error.trimmingWhitespace()[...]
        if let range = text.range(of: "execution error: ") {
            text = text[range.upperBound...]
        }
        // Drop a trailing status code like " (1)" or " (-128)".
        if text.hasSuffix(")"), let open = text.lastIndex(of: "("),
           Int(text[text.index(after: open)..<text.index(before: text.endIndex)]) != nil {
            text = text[..<open]
        }
        let message = text.trimmingWhitespace()
        return message.isEmpty ? "The administrator command failed." : message
    }
}
