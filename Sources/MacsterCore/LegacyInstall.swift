import Foundation

/// What Macster 0.1 may have left on this Mac.
///
/// The old version installed a root helper and a sudo rule for it, ran `caffeinate` as a launchd job, forced five
/// power settings to 0 on battery and on the power adapter, and kept a backup of the originals in the user's
/// Application Support folder.
public struct LegacyInstall: Equatable, Sendable {
    public static let helperPath = "/usr/local/libexec/macsterctl"
    public static let keepAwakeJobLabel = "io.github.macster.keepawake"
    public static let backupPathInHome = "Library/Application Support/Macster/power-settings-backup.json"

    public var helperInstalled: Bool
    public var keepAwakeJobLoaded: Bool
    /// The settings the old version saved before changing them, if it left a backup.
    public var backup: PowerSources?

    public init(helperInstalled: Bool, keepAwakeJobLoaded: Bool, backup: PowerSources?) {
        self.helperInstalled = helperInstalled
        self.keepAwakeJobLoaded = keepAwakeJobLoaded
        self.backup = backup
    }

    public static let none = LegacyInstall(helperInstalled: false, keepAwakeJobLoaded: false, backup: nil)

    public var isPresent: Bool {
        helperInstalled || keepAwakeJobLoaded || backup != nil
    }

    /// Reads the old backup file. Unknown settings and out-of-range values are dropped.
    public static func decodeBackup(_ data: Data) throws -> PowerSources {
        struct File: Decodable {
            var battery: [String: String]?
            var ac: [String: String]?
        }

        func profile(_ raw: [String: String]?) -> PowerProfile? {
            guard let raw else { return nil }
            var values: [PowerKey: Int] = [:]
            for (name, text) in raw {
                if let key = PowerKey(rawValue: name), let value = Int(text) {
                    values[key] = value
                }
            }
            let profile = PowerProfile(values)
            return profile.isEmpty ? nil : profile
        }

        let file = try JSONDecoder().decode(File.self, from: data)
        return PowerSources(battery: profile(file.battery), powerAdapter: profile(file.ac))
    }
}
