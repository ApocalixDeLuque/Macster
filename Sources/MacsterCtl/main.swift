import Darwin
import Foundation

private let version = "0.1.1"
private let launchLabel = "io.github.macster.keepawake"
private let backupRelativePath = "Library/Application Support/Macster/power-settings-backup.json"
private let restoredKeys = ["sleep", "disksleep", "displaysleep", "standby", "powernap"]

struct PowerBackup: Decodable {
    let battery: [String: String]
    let ac: [String: String]
}

enum MacsterCtlError: Error, LocalizedError {
    case rootRequired
    case unknownCommand(String)
    case commandFailed(String, Int32, String)

    var errorDescription: String? {
        switch self {
        case .rootRequired:
            return "enable and disable must run as root."
        case let .unknownCommand(command):
            return "Unknown command: \(command)"
        case let .commandFailed(command, status, output):
            let detail = output.trimmingCharacters(in: .whitespacesAndNewlines)
            return detail.isEmpty ? "\(command) failed with exit code \(status)." : "\(command) failed with exit code \(status): \(detail)"
        }
    }
}

@discardableResult
func run(_ executable: String, _ arguments: [String], allowFailure: Bool = false) throws -> String {
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

    if process.terminationStatus != 0 && !allowFailure {
        throw MacsterCtlError.commandFailed(([executable] + arguments).joined(separator: " "), process.terminationStatus, text)
    }

    return text
}

func requireRoot() throws {
    if geteuid() != 0 {
        throw MacsterCtlError.rootRequired
    }
}

func targetUID() -> String {
    ProcessInfo.processInfo.environment["SUDO_UID"] ?? String(getuid())
}

func targetHomeDirectory() -> URL? {
    if let uidString = ProcessInfo.processInfo.environment["SUDO_UID"],
       let uid = UInt32(uidString),
       let passwd = getpwuid(uid_t(uid)) {
        return URL(fileURLWithPath: String(cString: passwd.pointee.pw_dir), isDirectory: true)
    }

    if let user = ProcessInfo.processInfo.environment["SUDO_USER"],
       let passwd = getpwnam(user) {
        return URL(fileURLWithPath: String(cString: passwd.pointee.pw_dir), isDirectory: true)
    }

    return FileManager.default.homeDirectoryForCurrentUser
}

func backupURL() -> URL? {
    targetHomeDirectory()?.appendingPathComponent(backupRelativePath)
}

func submitKeepAwakeJob() throws {
    removeKeepAwakeJob()
    try run("/bin/launchctl", ["asuser", targetUID(), "/bin/launchctl", "submit", "-l", launchLabel, "--", "/usr/bin/caffeinate", "-d", "-i", "-s"])
}

func removeKeepAwakeJob() {
    _ = try? run("/bin/launchctl", ["asuser", targetUID(), "/bin/launchctl", "remove", launchLabel], allowFailure: true)
}

func enable() throws {
    try requireRoot()
    try submitKeepAwakeJob()
    try run("/usr/bin/pmset", ["-a", "sleep", "0", "disksleep", "0", "displaysleep", "0", "standby", "0", "powernap", "0"])
    try run("/usr/bin/pmset", ["-a", "disablesleep", "1"])
}

func disable() throws {
    try requireRoot()
    removeKeepAwakeJob()
    try run("/usr/bin/pmset", ["-a", "disablesleep", "0"])

    guard let url = backupURL(), FileManager.default.fileExists(atPath: url.path) else {
        return
    }

    let data = try Data(contentsOf: url)
    let backup = try JSONDecoder().decode(PowerBackup.self, from: data)

    if !backup.battery.isEmpty {
        try run("/usr/bin/pmset", ["-b"] + settingsArguments(backup.battery))
    }

    if !backup.ac.isEmpty {
        try run("/usr/bin/pmset", ["-c"] + settingsArguments(backup.ac))
    }

    try? FileManager.default.removeItem(at: url)
}

func settingsArguments(_ settings: [String: String]) -> [String] {
    restoredKeys.flatMap { key -> [String] in
        guard let value = settings[key], value.allSatisfy(\.isNumber) else {
            return []
        }

        return [key, value]
    }
}

do {
    let command = CommandLine.arguments.dropFirst().first ?? "help"

    switch command {
    case "version":
        print(version)
    case "enable":
        try enable()
    case "disable":
        try disable()
    case "help":
        print("macsterctl enable|disable|version")
    default:
        throw MacsterCtlError.unknownCommand(command)
    }
} catch {
    fputs("\((error as? LocalizedError)?.errorDescription ?? error.localizedDescription)\n", stderr)
    exit(1)
}
