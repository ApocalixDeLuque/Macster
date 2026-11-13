import Foundation
import Testing
@testable import MacsterCore

struct SetupPlanTests {
    private let legacyEverything = LegacyInstall(
        helperInstalled: true,
        keepAwakeJobLoaded: true,
        backup: PowerSources(battery: Fixtures.backupProfile, powerAdapter: Fixtures.backupProfile)
    )
    private let legacySettings = PowerSources(
        battery: Fixtures.legacySettingsProfile,
        powerAdapter: Fixtures.legacySettingsProfile
    )

    @Test func `undoes everything Macster 0.1 did, then installs the rule`() throws {
        let plan = SetupPlan(rule: try Fixtures.rule(), userID: 501, legacy: legacyEverything, currentSettings: legacySettings)
        #expect(plan.restore == PowerSources(battery: Fixtures.backupProfile, powerAdapter: Fixtures.backupProfile))
        #expect(plan.turnSleepBackOn)
        #expect(plan.stopLegacyKeepAwakeJob)
        #expect(plan.removeLegacyHelper)

        let commands = plan.script.split(separator: "\n").map(String.init)
        let expectedInOrder = [
            "/bin/launchctl asuser 501 /bin/launchctl remove io.github.macster.keepawake 2>/dev/null || true",
            "/usr/bin/pmset -b sleep 1 disksleep 10 displaysleep 0 standby 1 powernap 1 || warn 'could not restore the battery settings'",
            "/usr/bin/pmset -c sleep 1 disksleep 10 displaysleep 0 standby 1 powernap 1 || warn 'could not restore the power adapter settings'",
            "/usr/bin/pmset -a disablesleep 0 || warn 'could not turn sleep back on'",
            "/bin/rm -f /usr/local/libexec/macsterctl || warn 'could not delete the old helper'",
            "jappleseed ALL=(root) NOPASSWD: /usr/bin/pmset -a disablesleep 1, /usr/bin/pmset -a disablesleep 0",
            #"/bin/mv -f "$rule" /private/etc/sudoers.d/macster || exit 1"#,
        ]
        let positions = try expectedInOrder.map { line in try #require(commands.firstIndex(of: line), "missing: \(line)") }
        #expect(positions == positions.sorted())
    }

    @Test func `a fresh install only installs the rule`() throws {
        let plan = SetupPlan(rule: try Fixtures.rule(), userID: 501, legacy: .none, currentSettings: legacySettings)
        #expect(plan.restore.isEmpty)
        #expect(!plan.turnSleepBackOn)
        #expect(!plan.script.contains("pmset".appending(" -b")))
        #expect(!plan.script.contains("disablesleep 0 ||"))
        #expect(!plan.script.contains("macsterctl"))
        #expect(!plan.script.contains("launchctl"))
        #expect(plan.script.contains("visudo -cqf"))
    }

    @Test func `without a backup, only sources still holding the old values get macOS defaults`() throws {
        let legacy = LegacyInstall(helperInstalled: true, keepAwakeJobLoaded: false, backup: nil)
        let current = PowerSources(battery: Fixtures.legacySettingsProfile, powerAdapter: Fixtures.backupProfile)
        let plan = SetupPlan(rule: try Fixtures.rule(), userID: 501, legacy: legacy, currentSettings: current)
        #expect(plan.restore == PowerSources(battery: .batteryDefaults, powerAdapter: nil))
    }

    @Test func `leftover backup alone is still restored`() throws {
        let legacy = LegacyInstall(helperInstalled: false, keepAwakeJobLoaded: false, backup: legacyEverything.backup)
        let plan = SetupPlan(rule: try Fixtures.rule(), userID: 501, legacy: legacy, currentSettings: legacySettings)
        #expect(plan.restore == legacyEverything.backup)
        #expect(plan.turnSleepBackOn)
        #expect(!plan.removeLegacyHelper)
    }

    @Test func `battery settings are skipped on Macs without a battery`() throws {
        let current = PowerSources(battery: nil, powerAdapter: Fixtures.legacySettingsProfile)
        let plan = SetupPlan(rule: try Fixtures.rule(), userID: 501, legacy: legacyEverything, currentSettings: current)
        #expect(plan.restore == PowerSources(battery: nil, powerAdapter: Fixtures.backupProfile))
        #expect(!plan.script.contains("pmset -b"))
    }

    @Test func `if pmset can't be read, the backup is trusted as-is`() throws {
        let plan = SetupPlan(rule: try Fixtures.rule(), userID: 501, legacy: legacyEverything, currentSettings: PowerSources())
        #expect(plan.restore == legacyEverything.backup)
    }

    @Test func `the script is valid shell`() async throws {
        let plan = SetupPlan(rule: try Fixtures.rule(), userID: 501, legacy: legacyEverything, currentSettings: legacySettings)
        for script in [plan.script, RemovalPlan.script] {
            let output = try await ProcessRunner.run("/bin/sh", ["-n", "-c", script])
            #expect(output.succeeded, "\(output.stderr)")
        }
    }

    @Test func `the rule text inside the script is exactly the rule`() throws {
        let plan = SetupPlan(rule: try Fixtures.rule(), userID: 501, legacy: .none, currentSettings: PowerSources())
        let script = plan.script
        let start = try #require(script.range(of: "<<'MACSTER_RULE'\n"))
        let end = try #require(script.range(of: "\nMACSTER_RULE\n"))
        #expect(String(script[start.upperBound..<end.lowerBound]) + "\n" == plan.rule.contents)
    }
}
