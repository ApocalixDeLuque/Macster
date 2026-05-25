import Foundation
import SwiftUI

struct PowerStatus {
    enum Mode {
        case enabled
        case disabled
        case partial
        case unknown
    }

    static let unknown = PowerStatus(
        mode: .unknown,
        sleepDisabled: nil,
        sleepValue: nil,
        displaySleepValue: nil,
        keepAwakeJobRunning: false
    )

    let mode: Mode
    let sleepDisabled: Bool?
    let sleepValue: String?
    let displaySleepValue: String?
    let keepAwakeJobRunning: Bool

    var isEnabled: Bool {
        mode == .enabled
    }

    var badge: String {
        switch mode {
        case .enabled: "Enabled"
        case .disabled: "Disabled"
        case .partial: "Needs Sync"
        case .unknown: "Unknown"
        }
    }

    var title: String {
        switch mode {
        case .enabled:
            "Your Mac is set to stay awake when the lid closes."
        case .disabled:
            "Your Mac will use normal lid-close sleep behavior."
        case .partial:
            "Some keep-awake settings are active."
        case .unknown:
            "Macster could not read the current power state."
        }
    }

    var lidCloseLabel: String {
        switch sleepDisabled {
        case true: "Awake"
        case false: "Normal"
        case nil: "Unknown"
        }
    }

    var sleepLabel: String {
        sleepValue.map { $0 == "0" ? "Never" : "\($0) min" } ?? "Unknown"
    }

    var displayLabel: String {
        displaySleepValue.map { $0 == "0" ? "Never" : "\($0) min" } ?? "Unknown"
    }

    var tint: Color {
        switch mode {
        case .enabled: Color(red: 0.34, green: 0.92, blue: 0.56)
        case .disabled: Color(red: 0.62, green: 0.66, blue: 0.72)
        case .partial: Color(red: 1.00, green: 0.78, blue: 0.32)
        case .unknown: Color(red: 1.00, green: 0.45, blue: 0.42)
        }
    }
}

final class PowerService: @unchecked Sendable {
    private let activeLabel = "io.github.macster.keepawake"
    private let touchedKeys = ["sleep", "disksleep", "displaysleep", "standby", "powernap"]

    func readStatus() throws -> PowerStatus {
        let pmset = try Command.run("/usr/bin/pmset", ["-g"])
        let sleepDisabled = Self.extractValue(named: "SleepDisabled", from: pmset).map { $0 == "1" }
        let sleepValue = Self.extractValue(named: "sleep", from: pmset)
        let displaySleepValue = Self.extractValue(named: "displaysleep", from: pmset)
        let jobRunning = isAnyKeepAwakeJobRunning()

        let mode: PowerStatus.Mode
        if sleepDisabled == true {
            mode = .enabled
        } else if sleepDisabled == false && !jobRunning {
            mode = .disabled
        } else if sleepDisabled == nil {
            mode = .unknown
        } else {
            mode = .partial
        }

        return PowerStatus(
            mode: mode,
            sleepDisabled: sleepDisabled,
            sleepValue: sleepValue,
            displaySleepValue: displaySleepValue,
            keepAwakeJobRunning: jobRunning
        )
    }

    func enable() throws {
        let status = try readStatus()
        if status.sleepDisabled != true {
            try PowerBackupStore.saveCurrentSettingsIfNeeded(keys: touchedKeys)
        }

        removeKeepAwakeJobs()
        try Command.run("/bin/launchctl", ["submit", "-l", activeLabel, "--", "/usr/bin/caffeinate", "-d", "-i", "-s"])

        let command = "/usr/bin/pmset -a sleep 0 disksleep 0 displaysleep 0 standby 0 powernap 0 && /usr/bin/pmset -a disablesleep 1"
        try Command.runWithAdministratorPrivileges(command)
    }

    func disable() throws {
        removeKeepAwakeJobs()

        let command: String
        if let backup = try PowerBackupStore.load() {
            command = Self.restoreCommand(from: backup)
        } else {
            command = "/usr/bin/pmset -a disablesleep 0"
        }

        try Command.runWithAdministratorPrivileges(command)
        try PowerBackupStore.remove()
    }

    private func isAnyKeepAwakeJobRunning() -> Bool {
        let result = try? Command.run("/bin/launchctl", ["print", "gui/\(getuid())/\(activeLabel)"])
        return result?.contains("state = running") == true
    }

    private func removeKeepAwakeJobs() {
        _ = try? Command.run("/bin/launchctl", ["remove", activeLabel])
    }

    private static func restoreCommand(from backup: PowerBackup) -> String {
        var commands = ["/usr/bin/pmset -a disablesleep 0"]

        if !backup.battery.isEmpty {
            commands.append("/usr/bin/pmset -b \(settingsArguments(backup.battery))")
        }

        if !backup.ac.isEmpty {
            commands.append("/usr/bin/pmset -c \(settingsArguments(backup.ac))")
        }

        return commands.joined(separator: " && ")
    }

    private static func settingsArguments(_ settings: [String: String]) -> String {
        let order = ["sleep", "disksleep", "displaysleep", "standby", "powernap"]
        return order.compactMap { key in
            guard let value = settings[key] else { return nil }
            return "\(key) \(shellEscaped(value))"
        }.joined(separator: " ")
    }

    private static func shellEscaped(_ value: String) -> String {
        let safeCharacters = CharacterSet(charactersIn: "0123456789")
        if value.unicodeScalars.allSatisfy({ safeCharacters.contains($0) }) {
            return value
        }

        return "'\(value.replacingOccurrences(of: "'", with: "'\\''"))'"
    }

    private static func extractValue(named key: String, from output: String) -> String? {
        for line in output.split(separator: "\n") {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard trimmed.hasPrefix(key) else { continue }

            let suffix = trimmed.dropFirst(key.count).trimmingCharacters(in: .whitespaces)
            guard let firstToken = suffix.split(separator: " ").first else { return nil }
            return String(firstToken)
        }

        return nil
    }
}
