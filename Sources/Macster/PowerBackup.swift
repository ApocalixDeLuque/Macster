import Foundation

struct PowerBackup: Codable {
    let version: Int
    let createdAt: Date
    let battery: [String: String]
    let ac: [String: String]
}

enum PowerBackupStore {
    private static var backupURL: URL {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return support
            .appendingPathComponent("Macster", isDirectory: true)
            .appendingPathComponent("power-settings-backup.json")
    }

    static func saveCurrentSettingsIfNeeded(keys: [String]) throws {
        if FileManager.default.fileExists(atPath: backupURL.path) {
            return
        }

        let output = try Command.run("/usr/bin/pmset", ["-g", "custom"])
        let backup = parse(output, keys: keys)

        try FileManager.default.createDirectory(
            at: backupURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(backup).write(to: backupURL, options: .atomic)
    }

    static func load() throws -> PowerBackup? {
        guard FileManager.default.fileExists(atPath: backupURL.path) else {
            return nil
        }

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let data = try Data(contentsOf: backupURL)
        return try decoder.decode(PowerBackup.self, from: data)
    }

    static func remove() throws {
        guard FileManager.default.fileExists(atPath: backupURL.path) else {
            return
        }

        try FileManager.default.removeItem(at: backupURL)
    }

    private static func parse(_ output: String, keys: [String]) -> PowerBackup {
        var currentSection: String?
        var battery = [String: String]()
        var ac = [String: String]()

        for line in output.split(separator: "\n") {
            let trimmed = line.trimmingCharacters(in: .whitespaces)

            if trimmed == "Battery Power:" {
                currentSection = "battery"
                continue
            }

            if trimmed == "AC Power:" {
                currentSection = "ac"
                continue
            }

            guard let section = currentSection else { continue }

            for key in keys where trimmed.hasPrefix("\(key) ") {
                let value = trimmed
                    .dropFirst(key.count)
                    .trimmingCharacters(in: .whitespaces)
                    .split(separator: " ")
                    .first
                    .map(String.init)

                guard let value else { continue }

                if section == "battery" {
                    battery[key] = value
                } else {
                    ac[key] = value
                }
            }
        }

        return PowerBackup(version: 1, createdAt: Date(), battery: battery, ac: ac)
    }
}

