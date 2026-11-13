/// The one-time setup that runs behind the administrator password prompt.
///
/// It always installs `SudoRule`. If Macster 0.1 is still around, it first undoes everything that version did:
/// stops its `caffeinate` job, restores the power settings it overwrote, turns sleep back on, and deletes its root
/// helper. Restoring is best effort — a failure there is reported as a warning — but installing the rule is not:
/// the rule is validated with `visudo` before it goes live, and removed again if sudo rejects the result.
public struct SetupPlan: Equatable, Sendable {
    public var rule: SudoRule
    public var userID: UInt32
    public var restore: PowerSources
    public var turnSleepBackOn: Bool
    public var stopLegacyKeepAwakeJob: Bool
    public var removeLegacyHelper: Bool

    public static let prompt = "Macster needs your password once so it can turn lid-close sleep on and off."

    public init(rule: SudoRule, userID: UInt32, legacy: LegacyInstall, currentSettings: PowerSources) {
        self.rule = rule
        self.userID = userID
        restore = Self.settingsToRestore(legacy: legacy, current: currentSettings)
        turnSleepBackOn = legacy.isPresent
        stopLegacyKeepAwakeJob = legacy.keepAwakeJobLoaded
        removeLegacyHelper = legacy.helperInstalled
    }

    static func settingsToRestore(legacy: LegacyInstall, current: PowerSources) -> PowerSources {
        // Only touch power sources this Mac has. If `pmset` couldn't be read at all, trust the backup.
        let knowsSources = current.battery != nil || current.powerAdapter != nil
        func ifPresent(_ profile: PowerProfile?, on source: PowerProfile?) -> PowerProfile? {
            guard let profile, !profile.isEmpty else { return nil }
            return knowsSources && source == nil ? nil : profile
        }

        if let backup = legacy.backup {
            return PowerSources(
                battery: ifPresent(backup.battery, on: current.battery),
                powerAdapter: ifPresent(backup.powerAdapter, on: current.powerAdapter)
            )
        }

        // No backup, but the old version's values may still be in place. Put back macOS defaults for those sources.
        guard legacy.helperInstalled else { return PowerSources() }
        return PowerSources(
            battery: current.battery?.hasLegacyKeepAwakeValues == true ? .batteryDefaults : nil,
            powerAdapter: current.powerAdapter?.hasLegacyKeepAwakeValues == true ? .powerAdapterDefaults : nil
        )
    }

    /// What the script does, in plain language, for logs and `--diagnose`.
    public var steps: [String] {
        var steps: [String] = []
        if stopLegacyKeepAwakeJob { steps.append("Stop Macster 0.1's caffeinate job") }
        if let battery = restore.battery { steps.append("Restore battery settings: \(battery.pmsetArguments.joined(separator: " "))") }
        if let adapter = restore.powerAdapter { steps.append("Restore power adapter settings: \(adapter.pmsetArguments.joined(separator: " "))") }
        if turnSleepBackOn { steps.append("Turn sleep back on (pmset -a disablesleep 0)") }
        if removeLegacyHelper { steps.append("Delete Macster 0.1's root helper at \(LegacyInstall.helperPath)") }
        steps.append("Install \(SudoRule.path), allowing only `\(SleepCommand.commandLine(sleepDisabled: true))` and `\(SleepCommand.commandLine(sleepDisabled: false))`")
        return steps
    }

    public var script: String {
        var lines = [
            "set -u",
            "PATH=/usr/bin:/bin:/usr/sbin:/sbin",
            #"warn() { echo "warning: $1"; }"#,
        ]
        if stopLegacyKeepAwakeJob {
            lines.append("/bin/launchctl asuser \(userID) /bin/launchctl remove \(LegacyInstall.keepAwakeJobLabel) 2>/dev/null || true")
        }
        if let battery = restore.battery {
            lines.append("/usr/bin/pmset -b \(battery.pmsetArguments.joined(separator: " ")) || warn 'could not restore the battery settings'")
        }
        if let adapter = restore.powerAdapter {
            lines.append("/usr/bin/pmset -c \(adapter.pmsetArguments.joined(separator: " ")) || warn 'could not restore the power adapter settings'")
        }
        if turnSleepBackOn {
            lines.append("/usr/bin/pmset -a disablesleep 0 || warn 'could not turn sleep back on'")
        }
        if removeLegacyHelper {
            lines.append("/bin/rm -f \(LegacyInstall.helperPath) || warn 'could not delete the old helper'")
            lines.append("/bin/rmdir /usr/local/libexec 2>/dev/null || true")
        }
        lines += [
            "/bin/mkdir -p /private/etc/sudoers.d || exit 1",
            // sudo ignores files whose names contain a dot, so the rule can't take effect before it's validated.
            "rule=$(/usr/bin/mktemp /private/etc/sudoers.d/.macster.XXXXXX) || exit 1",
            #"trap '/bin/rm -f "$rule"' EXIT"#,
            #"/bin/cat > "$rule" <<'MACSTER_RULE'"#,
            rule.contents.trimmingTrailingNewlines(),
            "MACSTER_RULE",
            #"/usr/sbin/chown root:wheel "$rule" && /bin/chmod 0440 "$rule" || exit 1"#,
            #"/usr/sbin/visudo -cqf "$rule" || { echo 'the new sudo rule failed validation' >&2; exit 1; }"#,
            #"/bin/mv -f "$rule" \#(SudoRule.path) || exit 1"#,
            "trap - EXIT",
            #"/usr/sbin/visudo -cq || { /bin/rm -f \#(SudoRule.path); echo 'sudo rejected the new rule, so Macster removed it' >&2; exit 1; }"#,
        ]
        return lines.joined(separator: "\n") + "\n"
    }

    public var privilegedScript: PrivilegedScript {
        PrivilegedScript(script: script, prompt: Self.prompt)
    }
}

/// Undoes setup: turns sleep back on and deletes Macster's sudo rule.
public enum RemovalPlan {
    public static let script = """
    /usr/bin/pmset -a disablesleep 0
    /bin/rm -f \(SudoRule.path)

    """

    public static let privilegedScript = PrivilegedScript(
        script: script,
        prompt: "Macster needs your password to remove its permission to change sleep settings."
    )
}

extension String {
    func trimmingTrailingNewlines() -> String {
        var text = self
        while text.last?.isNewline == true { text.removeLast() }
        return text
    }
}
