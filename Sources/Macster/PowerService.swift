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
        keepAwakeJobRunning: false,
        helperInstalled: false
    )

    let mode: Mode
    let sleepDisabled: Bool?
    let sleepValue: String?
    let displaySleepValue: String?
    let keepAwakeJobRunning: Bool
    let helperInstalled: Bool

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
            "Lid-close sleep is disabled."
        case .disabled:
            "Normal lid-close sleep is enabled."
        case .partial:
            "Some keep-awake settings are active."
        case .unknown:
            "Macster could not read the current power state."
        }
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
    private let helperPath = "/usr/local/libexec/macsterctl"
    private let sudoersPath = "/etc/sudoers.d/macster"
    private let touchedKeys = ["sleep", "disksleep", "displaysleep", "standby", "powernap"]

    func readStatus() throws -> PowerStatus {
        let pmset = try Command.run("/usr/bin/pmset", ["-g"])
        let sleepDisabled = Self.extractValue(named: "SleepDisabled", from: pmset).map { $0 == "1" }
        let sleepValue = Self.extractValue(named: "sleep", from: pmset)
        let displaySleepValue = Self.extractValue(named: "displaysleep", from: pmset)
        let jobRunning = isAnyKeepAwakeJobRunning()
        let helperInstalled = isCurrentHelperInstalled()

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
            keepAwakeJobRunning: jobRunning,
            helperInstalled: helperInstalled
        )
    }

    func enable() throws {
        try installPrivilegedHelperIfNeeded()

        let status = try readStatus()
        if status.sleepDisabled != true {
            try PowerBackupStore.saveCurrentSettingsIfNeeded(keys: touchedKeys)
        }

        try runPrivilegedHelper("enable")
    }

    func disable() throws {
        try installPrivilegedHelperIfNeeded()
        try runPrivilegedHelper("disable")
    }

    private func isAnyKeepAwakeJobRunning() -> Bool {
        let result = try? Command.run("/bin/launchctl", ["print", "gui/\(getuid())/\(activeLabel)"])
        return result?.contains("state = running") == true
    }

    private func isCurrentHelperInstalled() -> Bool {
        guard FileManager.default.isExecutableFile(atPath: helperPath) else {
            return false
        }

        guard let output = try? Command.run(helperPath, ["version"]) else {
            return false
        }

        return output.trimmingCharacters(in: .whitespacesAndNewlines) == MacsterVersion.current
    }

    private func installPrivilegedHelperIfNeeded() throws {
        guard !isCurrentHelperInstalled() else {
            return
        }

        guard let bundledHelper = Bundle.main.url(forResource: "macsterctl", withExtension: nil) else {
            throw PowerError.missingBundledHelper
        }

        let userName = NSUserName()
        guard Self.isSafeUserName(userName) else {
            throw PowerError.unsafeUserName(userName)
        }

        let tempDirectory = URL(fileURLWithPath: "/private/tmp", isDirectory: true)
        let installID = UUID().uuidString
        let installer = tempDirectory.appendingPathComponent("macster-install-\(installID).sh")
        let helperCopy = tempDirectory.appendingPathComponent("macsterctl-\(installID)")

        try? FileManager.default.removeItem(at: installer)
        try? FileManager.default.removeItem(at: helperCopy)

        try FileManager.default.copyItem(at: bundledHelper, to: helperCopy)
        try Self.installScript.write(to: installer, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: installer.path)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: helperCopy.path)

        defer {
            try? FileManager.default.removeItem(at: installer)
            try? FileManager.default.removeItem(at: helperCopy)
        }

        let command = [
            "/bin/bash",
            Command.shellEscaped(installer.path),
            Command.shellEscaped(helperCopy.path),
            Command.shellEscaped(userName),
            Command.shellEscaped(MacsterVersion.current),
            Command.shellEscaped(sudoersPath)
        ].joined(separator: " ")

        try Command.runWithAdministratorPrivileges(command)
    }

    private func runPrivilegedHelper(_ action: String) throws {
        do {
            try Command.run("/usr/bin/sudo", ["-n", helperPath, action])
        } catch {
            try installPrivilegedHelperIfNeeded()
            try Command.run("/usr/bin/sudo", ["-n", helperPath, action])
        }
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

    private static func isSafeUserName(_ userName: String) -> Bool {
        let allowed = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789._-")
        return !userName.isEmpty && userName.unicodeScalars.allSatisfy { allowed.contains($0) }
    }

    private static let installScript = """
    #!/bin/bash
    set -euo pipefail

    helper_source="$1"
    target_user="$2"
    expected_version="$3"
    sudoers_path="$4"

    case "$target_user" in
      ""|*[!abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789._-]*)
        echo "Unsafe user name: $target_user" >&2
        exit 64
        ;;
    esac

    /usr/bin/install -d -o root -g wheel -m 755 /usr/local/libexec
    /usr/bin/install -o root -g wheel -m 755 "$helper_source" /usr/local/libexec/macsterctl

    installed_version="$(/usr/local/libexec/macsterctl version)"
    if [[ "$installed_version" != "$expected_version" ]]; then
      echo "Installed helper version mismatch: $installed_version" >&2
      exit 65
    fi

    /bin/mkdir -p /etc/sudoers.d
    tmp="$(/usr/bin/mktemp /tmp/macster-sudoers.XXXXXX)"
    /bin/cat > "$tmp" <<EOF
    # Macster allows only its narrow local helper commands without repeated prompts.
    $target_user ALL=(root) NOPASSWD: /usr/local/libexec/macsterctl enable, /usr/local/libexec/macsterctl disable
    EOF

    /usr/sbin/visudo -cf "$tmp" >/dev/null
    /usr/sbin/chown root:wheel "$tmp"
    /bin/chmod 440 "$tmp"
    /bin/mv "$tmp" "$sudoers_path"
    """
}
