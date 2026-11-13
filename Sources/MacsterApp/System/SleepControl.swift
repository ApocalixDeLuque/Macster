import Foundation
import MacsterCore

enum SleepControlError: LocalizedError, Equatable {
    case permissionMissing
    case commandFailed(String)
    case notApplied
    case setupCanceled
    case setupFailed(String)
    case watchdogUnavailable(String)

    var errorDescription: String? {
        switch self {
        case .permissionMissing:
            "Macster no longer has permission to change sleep. Set it up again."
        case .commandFailed(let detail):
            "macOS didn't accept the change: \(detail)"
        case .notApplied:
            "macOS didn't apply the change. Try again."
        case .setupCanceled:
            "Setup canceled. Macster can't change sleep until it's set up."
        case .setupFailed(let detail):
            "Setup didn't finish: \(detail)"
        case .watchdogUnavailable(let detail):
            "Macster couldn't start its safety helper, so it left sleep alone. \(detail)"
        }
    }
}

/// Changes the system's sleep setting through Macster's two-command sudo rule.
enum SleepControl {
    static func setSleepDisabled(_ disabled: Bool, timeout: Duration = .seconds(15)) async throws {
        let output: ProcessOutput
        do {
            output = try await ProcessRunner.run(
                SleepCommand.sudoPath,
                SleepCommand.sudoArguments(sleepDisabled: disabled),
                timeout: timeout
            )
        } catch {
            throw SleepControlError.commandFailed(error.localizedDescription)
        }

        guard output.succeeded else {
            if output.stderr.contains("password is required") || output.stderr.contains("terminal is required") {
                throw SleepControlError.permissionMissing
            }
            let detail = output.stderr.trimmingCharacters(in: .whitespacesAndNewlines)
            throw SleepControlError.commandFailed(
                output.timedOut ? "pmset timed out." : (detail.isEmpty ? "pmset exited with status \(output.status)." : detail)
            )
        }
    }

    /// Whether Macster can change sleep without a password.
    ///
    /// Reads the rules with `sudo -n -l`. Some sudo configurations need a password just to list rules, so when the rule
    /// file exists and `probe` is set, access is proven instead by writing the value sleep already has, which changes
    /// nothing.
    static func hasPasswordlessAccess(probe currentValue: Bool?) async -> Bool {
        if let listing = try? await ProcessRunner.run(SleepCommand.sudoPath, ["-n", "-l"], timeout: .seconds(10)),
           listing.succeeded, SudoRule.listingGrantsAccess(listing.stdout) {
            return true
        }
        guard let currentValue, FileManager.default.fileExists(atPath: SudoRule.path) else { return false }
        do {
            try await setSleepDisabled(currentValue, timeout: .seconds(10))
            return true
        } catch {
            return false
        }
    }

    /// Runs `script` as root behind the administrator password prompt and returns its warnings.
    static func runPrivileged(_ script: PrivilegedScript) async throws -> [String] {
        let output = try await ProcessRunner.run("/usr/bin/osascript", ["-e", script.appleScript()], timeout: .seconds(600))
        guard output.succeeded else {
            if PrivilegedScript.isCancellation(output.stderr) { throw SleepControlError.setupCanceled }
            throw SleepControlError.setupFailed(PrivilegedScript.message(fromOsascriptError: output.stderr))
        }
        // `do shell script` returns the script's stdout with carriage returns between lines.
        return output.stdout
            .split(whereSeparator: \.isNewline)
            .compactMap { line in line.hasPrefix("warning: ") ? String(line.dropFirst("warning: ".count)) : nil }
    }
}
