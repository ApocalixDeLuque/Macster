import Foundation
import MacsterCore

/// Finds and cleans up what Macster 0.1 left behind.
enum LegacyScanner {
    static var backupURL: URL {
        FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(LegacyInstall.backupPathInHome)
    }

    static func scan() async -> LegacyInstall {
        let backup = (try? Data(contentsOf: backupURL)).flatMap { try? LegacyInstall.decodeBackup($0) }
        return LegacyInstall(
            helperInstalled: FileManager.default.fileExists(atPath: LegacyInstall.helperPath),
            keepAwakeJobLoaded: await isKeepAwakeJobLoaded(),
            backup: backup
        )
    }

    /// The current `pmset -g custom` values for the settings Macster 0.1 changed.
    static func currentSettings() async -> PowerSources {
        guard let output = try? await ProcessRunner.run("/usr/bin/pmset", ["-g", "custom"], timeout: .seconds(10)),
              output.succeeded
        else { return PowerSources() }
        return PowerSources(pmsetCustomOutput: output.stdout)
    }

    /// Removes what the old version left in the user's own account. Runs after setup, needs no password.
    static func removeUserLeftovers() async {
        if await isKeepAwakeJobLoaded() {
            _ = try? await ProcessRunner.run("/bin/launchctl", ["remove", LegacyInstall.keepAwakeJobLabel], timeout: .seconds(10))
        }

        let fileManager = FileManager.default
        try? fileManager.removeItem(at: backupURL)
        let folder = backupURL.deletingLastPathComponent()
        if (try? fileManager.contentsOfDirectory(atPath: folder.path))?.isEmpty == true {
            try? fileManager.removeItem(at: folder)
        }

        // The old window-based app saved its window position.
        let defaults = UserDefaults.standard
        if let domain = Bundle.main.bundleIdentifier.flatMap(defaults.persistentDomain(forName:)) {
            for key in domain.keys where key.hasPrefix("NSWindow Frame") {
                defaults.removeObject(forKey: key)
            }
        }
    }

    private static func isKeepAwakeJobLoaded() async -> Bool {
        let output = try? await ProcessRunner.run(
            "/bin/launchctl",
            ["print", "gui/\(getuid())/\(LegacyInstall.keepAwakeJobLabel)"],
            timeout: .seconds(10)
        )
        return output?.succeeded == true
    }
}
