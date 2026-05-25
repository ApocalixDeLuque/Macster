import Foundation

enum PowerError: Error, LocalizedError {
    case commandFailed(command: String, status: Int32, output: String)

    var errorDescription: String? {
        switch self {
        case let .commandFailed(command, status, output):
            let detail = output.trimmingCharacters(in: .whitespacesAndNewlines)
            if detail.isEmpty {
                return "\(command) failed with exit code \(status)."
            }

            return "\(command) failed with exit code \(status): \(detail)"
        }
    }

    static func readableMessage(from error: Error) -> String {
        if let localized = error as? LocalizedError, let description = localized.errorDescription {
            if description.contains("User canceled") || description.contains("(-128)") {
                return "Canceled."
            }

            return description
        }

        return error.localizedDescription
    }
}

enum Command {
    @discardableResult
    static func run(_ executable: String, _ arguments: [String] = []) throws -> String {
        let process = Process()
        let output = Pipe()

        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        process.standardOutput = output
        process.standardError = output

        try process.run()
        process.waitUntilExit()

        let data = output.fileHandleForReading.readDataToEndOfFile()
        let text = String(data: data, encoding: .utf8) ?? ""

        guard process.terminationStatus == 0 else {
            throw PowerError.commandFailed(
                command: ([executable] + arguments).joined(separator: " "),
                status: process.terminationStatus,
                output: text
            )
        }

        return text
    }

    @discardableResult
    static func runWithAdministratorPrivileges(_ shellCommand: String) throws -> String {
        let script = "do shell script \"\(appleScriptEscaped(shellCommand))\" with administrator privileges"
        return try run("/usr/bin/osascript", ["-e", script])
    }

    private static func appleScriptEscaped(_ value: String) -> String {
        value
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
    }
}

