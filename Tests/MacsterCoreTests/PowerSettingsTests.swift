import Foundation
import Testing
@testable import MacsterCore

struct PowerSettingsTests {
    @Test func `parses both power sources from pmset -g custom`() {
        let sources = PowerSources(pmsetCustomOutput: Fixtures.pmsetCustomWithLegacyOn)
        #expect(sources.battery == Fixtures.legacySettingsProfile)
        #expect(sources.powerAdapter == Fixtures.legacySettingsProfile)
        #expect(sources.battery?.hasLegacyKeepAwakeValues == true)
    }

    @Test func `ignores other sections and settings with spaces in their names`() {
        let output = """
        Battery Power:
         Sleep On Power Button 1
         sleep                5
        UPS Power:
         sleep                9
        AC Power:
         displaysleep         10 (display sleep prevented by caffeinate)
        """
        let sources = PowerSources(pmsetCustomOutput: output)
        #expect(sources.battery == PowerProfile([.sleep: 5]))
        #expect(sources.powerAdapter == PowerProfile([.displaysleep: 10]))
        #expect(sources.battery?.hasLegacyKeepAwakeValues == false)
    }

    @Test func `a Mac without a battery has no battery profile`() {
        let sources = PowerSources(pmsetCustomOutput: "AC Power:\n sleep 1\n")
        #expect(sources.battery == nil)
        #expect(sources.powerAdapter == PowerProfile([.sleep: 1]))
    }

    @Test func `empty or unexpected output parses to nothing`() {
        #expect(PowerSources(pmsetCustomOutput: "").isEmpty)
        #expect(PowerSources(pmsetCustomOutput: "pmset: command not found").isEmpty)
    }

    @Test func `pmset arguments come out in a fixed order`() {
        #expect(Fixtures.backupProfile.pmsetArguments == [
            "sleep", "1", "disksleep", "10", "displaysleep", "0", "standby", "1", "powernap", "1",
        ])
    }

    @Test func `out-of-range values are dropped`() {
        let profile = PowerProfile([.sleep: -1, .standby: 7, .powernap: 1, .displaysleep: 100_000])
        #expect(profile == PowerProfile([.powernap: 1]))
    }
}

struct LegacyBackupTests {
    @Test func `decodes the backup file Macster 0.1 wrote`() throws {
        let backup = try LegacyInstall.decodeBackup(Data(Fixtures.legacyBackupJSON.utf8))
        #expect(backup.battery == Fixtures.backupProfile)
        #expect(backup.powerAdapter == Fixtures.backupProfile)
    }

    @Test func `drops unknown settings and values that aren't valid numbers`() throws {
        let json = #"{"battery": {"sleep": "abc", "displaysleep": "-5", "standby": "7", "hibernatemode": "25", "powernap": "0"}}"#
        let backup = try LegacyInstall.decodeBackup(Data(json.utf8))
        #expect(backup.battery == PowerProfile([.powernap: 0]))
        #expect(backup.powerAdapter == nil)
    }

    @Test func `a backup with nothing usable restores nothing`() throws {
        let backup = try LegacyInstall.decodeBackup(Data(#"{"battery": {"sleep": "; rm -rf /"}}"#.utf8))
        #expect(backup.isEmpty)
    }

    @Test func `malformed JSON throws`() {
        #expect(throws: (any Error).self) {
            try LegacyInstall.decodeBackup(Data("{".utf8))
        }
    }
}
